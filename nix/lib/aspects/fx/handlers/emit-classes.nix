# Effect handler: emit-classes
# Iterates class keys and sends emit-class per module element.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity argClass;
  inherit (den.lib.aspects.fx.contentUtil) unwrapContentValuesList unwrapContentValuesAll;
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

  schema = den.schema or { };

  # The contexts a class module emits under at a scope. A module requiring an
  # entity kind that is a strict DESCENDANT of the scope's kind, and absent from
  # ctx (a host-scope `nixos = { user, ... }:`), emits once per instance of that
  # kind, bound in ctx; with no instance it emits nothing. Only that module
  # fans: the aspect's other content stays at the scope (#629). Kinds fan
  # shallowest first, so a transitive descendant enumerates off its bound
  # parent; one whose parent is not reachable stays missing, and the module
  # stays unsatisfied, as before. `fan` lists the kinds bound for this context.
  fanKinds =
    { ctx, scopeKind }:
    module:
    let
      args = if builtins.isFunction module then builtins.functionArgs module else { };
    in
    builtins.filter (
      a:
      !args.${a}
      && schemaEntityKindsSet ? ${a}
      && !(ctx ? ${a})
      && argClass.isDescendantOf schema scopeKind a
    ) (builtins.attrNames args);

  fanContexts =
    { ctx, scopeKind }:
    module:
    let
      missing = fanKinds { inherit ctx scopeKind; } module;
      expand =
        acc: kinds:
        let
          fanable = builtins.filter (k: acc.ctx ? ${argClass.parentKindOf schema scopeKind k}) kinds;
          k = builtins.head fanable;
          parent = acc.ctx.${argClass.parentKindOf schema scopeKind k};
        in
        if fanable == [ ] then
          [ acc ]
        else
          builtins.concatMap (
            child:
            expand {
              ctx = acc.ctx // {
                ${k} = child;
              };
              fan = acc.fan ++ [ { inherit k child; } ];
            } (builtins.filter (x: x != k) kinds)
          ) (argClass.childrenOf parent k);
    in
    if missing == [ ] then
      [
        {
          inherit ctx;
          fan = [ ];
        }
      ]
    else
      expand {
        inherit ctx;
        fan = [ ];
      } missing;

  emitClassEntry =
    {
      class,
      identity,
      module,
      ctx,
      aspectPolicy,
      globalPolicy,
      isContextDependent,
      sharedFanOutFor ? null,
      defPos ? null,
    }:
    fx.send "emit-class" (
      {
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
      }
      // lib.optionalAttrs (sharedFanOutFor != null) { inherit sharedFanOutFor; }
      // lib.optionalAttrs (defPos != null) { inherit defPos; }
    );

  emitClassKey =
    aspect: ctx: fanCtx: aspectPolicy: globalPolicy: contextDep: nodeIdentity: k:
    let
      # Several definitions of a key are merged into one module, which would
      # hide a definition naming a kind an ancestor scope fans: it could not
      # fan here, and its per-instance copies would share one key. When one
      # does, each emits on its own, at the fanning scope and at the kind's own
      # scope alike, so a fanned copy and the descendant's own copy are keyed
      # alike.
      defs = unwrapContentValuesAll aspect.${k};
      hasParentKind = kind: builtins.length (argClass.ancestorChain schema kind) > 1;
      namesEntity =
        m:
        builtins.any hasParentKind (namedEntityArgs ctx m)
        ||
          fanKinds {
            inherit ctx;
            inherit (fanCtx) scopeKind;
          } m != [ ];
      modules =
        if builtins.length defs > 1 && builtins.any namesEntity defs then
          defs
        else
          unwrapContentValuesList aspect.${k};
      isMulti = builtins.length modules > 1;
      mkEntry =
        idx: module:
        let
          mkFanEntry =
            fc:
            let
              entityArgs = namedEntityArgs fc.ctx module;
              baseIdFor = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
              # A fanned copy of content a descendant kind also includes is
              # marked as bind.nix marks a fanned aspect (#694 §11a R6).
              shared = lib.findFirst (b: fanCtx.sharedWith b.k && b.child ? id_hash) null (
                lib.reverseList fc.fan
              );
            in
            emitClassEntry {
              class = k;
              identity = baseIdFor + entityIdSuffix fc.ctx entityArgs;
              inherit
                module
                aspectPolicy
                globalPolicy
                ;
              inherit (fc) ctx;
              # Content naming an entity kind is per-instance ⇒ keep the {…} suffix
              # through identity computation (wrap-classes.nix finalIdentity).
              isContextDependent = contextDep || entityArgs != [ ];
              sharedFanOutFor =
                if shared != null then
                  "${fanCtx.hostIdHash}>${shared.child.id_hash}"
                else
                  aspect.meta.__sharedFanOutFor or null;
              # An anonymous aspect's definition position, a stable key the
              # transition warning reads (#694 F2); its walk identity is not.
              defPos = if aspect.__walkStamped or false then builtins.unsafeGetAttrPos k aspect else null;
            };
        in
        fx.seq (
          map mkFanEntry (
            fanContexts {
              inherit ctx;
              inherit (fanCtx) scopeKind;
            } module
          )
        );
    in
    fx.seq (lib.imap0 mkEntry modules);

  # One entry per definition: quirk values accumulate at assembly, so several
  # definitions of the same pipe key on one aspect must stay separate.
  emitPipeKey =
    aspect: ctx: contextDep: nodeIdentity: k:
    let
      modules = unwrapContentValuesAll aspect.${k};
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
        # What fanContexts needs from the scope: its entity kind, and whether
        # this aspect's schema-include root is also included by a kind (as
        # bind.nix's sharedWithDescendant reads it).
        scopeChain = ((state.scopedIncludesChain or (_: { })) null).${currentScope} or [ ];
        includeRoot = if builtins.length scopeChain >= 2 then builtins.elemAt scopeChain 1 else null;
        fanCtx = {
          # The scope's own host, as bind.nix reads it (availRecords.host).
          hostIdHash = (scopeCtx.host or { }).id_hash or "";
          scopeKind =
            if currentScope == null then
              null
            else
              ((state.scopeEntityKind or (_: { })) null).${currentScope} or null;
          sharedWith =
            kind:
            includeRoot != null
            && builtins.any (inc: identity.key inc == includeRoot) ((schema.${kind} or { }).includes or [ ]);
        };
      in
      {
        resume = fx.seq (
          (map (emitClassKey aspect ctx fanCtx aspectPolicy globalPolicy contextDep nodeIdentity) classKeys)
          ++ (map (emitPipeKey aspect ctx contextDep nodeIdentity) pipeKeys)
        );
        inherit state;
      };
  };
}
