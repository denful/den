# Effect handler: emit-classes
# Iterates class keys and sends emit-class per module element.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects.fx.contentUtil) unwrapContentValuesList;
  inherit (den.lib.schemaUtil) schemaEntityKindsSet;

  inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;

  isContextDep =
    aspect: ctx:
    let
      resolvedArgs = aspect.__parametricResolvedArgs or [ ];
    in
    (resolvedArgs != [ ] && builtins.any (ak: ctx ? ${ak}) resolvedArgs)
    || (aspect.meta.contextDependent or false);

  # Entity kinds a class-content module NAMES as function args AND that are
  # present in the emitting scope's context. Such content is per-instance of
  # those entities: key its identity by them so it neither over-collapses nor
  # over-fans.
  #   - `nixos = { user, ... }:`  → keyed {user=<u>}  → fans per user (the bug
  #     this fixes: a static user-scoped aspect's host-class content used to
  #     collapse N users → 1 at the shared host merge).
  #   - `nixos = { host, ... }:`  → keyed {host=<h>}  → dedups across every scope
  #     the aspect is delivered from (host scope + the user scopes it reaches via
  #     home content), so host-targeted content stays one module.
  #   - `nixos = { persist, ... }:` / `_:` (no entity kind) → no suffix → singular
  #     (shared infra aspects like impermanence keep deduping; no double option
  #     declaration).
  # Relies on the emit ctx being the authoritative scope context (see handler) —
  # otherwise `ctx ? <kind>` is unreliable and the keying is path-dependent.
  namedEntityArgs =
    ctx: module:
    if builtins.isFunction module then
      builtins.filter (a: (schemaEntityKindsSet ? ${a}) && (ctx ? ${a})) (
        builtins.attrNames (builtins.functionArgs module)
      )
    else
      [ ];

  # Per-instance identity suffix for the named entity kinds, e.g.
  # "/{host=cortex,user=sini}". Empty when the content names no entity kind.
  # attrNames is already sorted, so the suffix is deterministic.
  entityIdSuffix =
    ctx: args:
    if args == [ ] then
      ""
    else
      "/{" + lib.concatStringsSep "," (map (a: "${a}=${ctx.${a}.name or "?"}") args) + "}";

  emitClassEntry =
    {
      class,
      identity,
      module,
      ctx,
      aspectPolicy,
      globalPolicy,
      isContextDependent,
    }:
    fx.send "emit-class" {
      inherit
        class
        identity
        module
        ctx
        aspectPolicy
        globalPolicy
        isContextDependent
        ;
      __rawEntry = true;
    };

  emitClassKey =
    aspect: ctx: aspectPolicy: globalPolicy: contextDep: nodeIdentity: k:
    let
      modules = unwrapContentValuesList aspect.${k};
      isMulti = builtins.length modules > 1;
      mkEntry =
        idx: module:
        let
          entityArgs = namedEntityArgs ctx module;
          baseId = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
        in
        emitClassEntry {
          class = k;
          identity = baseId + entityIdSuffix ctx entityArgs;
          inherit
            module
            ctx
            aspectPolicy
            globalPolicy
            ;
          # Content naming an entity kind is per-instance ⇒ keep the {…} suffix
          # through identity computation (wrap-classes.nix finalIdentity).
          isContextDependent = contextDep || entityArgs != [ ];
        };
    in
    fx.seq (lib.imap0 mkEntry modules);

  emitPipeKey =
    aspect: ctx: contextDep: nodeIdentity: k:
    let
      modules = unwrapContentValuesList aspect.${k};
      isMulti = builtins.length modules > 1;
      mkEntry =
        idx: module:
        fx.send "emit-class" {
          class = k;
          identity = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
          inherit module ctx;
          aspectPolicy = null;
          globalPolicy = null;
          isContextDependent = contextDep;
          __rawEntry = true;
          __isPipeEntry = true;
        };
    in
    fx.seq (lib.imap0 mkEntry modules);
in
{
  emitClassesHandler = {
    "emit-classes" =
      { param, state }:
      let
        aspect = param.aspect;
        classKeys = param.classKeys;
        pipeKeys = param.pipeKeys or [ ];
        nodeIdentity = param.identity;
        # Authoritative emit context: the scope's own context from pipeline state
        # (host + any descendant entity bindings), the SAME source bind.nix reads
        # — not the per-aspect `__scopeHandlers`, which is only populated for
        # parametric aspects / propagated includes and is ABSENT for a static
        # aspect on a static include chain (→ empty ctx → path-dependent identity
        # and the N→1 host-class collapse). The aspect's own handlers (fan-out
        # child bindings) layer on top so they still win. Child scopes only; the
        # root scope keeps the historic handler-only path (byte-stable).
        currentScope = state.currentScope or null;
        rootScopeId = state.rootScopeId or null;
        isChildScope = currentScope != null && rootScopeId != null && currentScope != rootScopeId;
        scopeCtx =
          if isChildScope then
            let
              ctxs = (state.scopeContexts or (_: { })) null;
              entityCls = ((state.scopeEntityClass or (_: { })) null).${currentScope} or null;
            in
            (ctxs.${currentScope} or { }) // lib.optionalAttrs (entityCls != null) { class = entityCls; }
          else
            { };
        ctx = scopeCtx // ctxFromHandlers (aspect.__scopeHandlers or { });
        aspectPolicy = aspect.meta.collisionPolicy or null;
        globalPolicy = den.config.classModuleCollisionPolicy or "error";
        contextDep = isContextDep aspect ctx;
      in
      {
        resume = fx.seq (
          (map (emitClassKey aspect ctx aspectPolicy globalPolicy contextDep nodeIdentity) classKeys)
          ++ (map (emitPipeKey aspect ctx contextDep nodeIdentity) pipeKeys)
        );
        inherit state;
      };
  };
}
