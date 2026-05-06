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

  inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;

  isContextDep =
    aspect: ctx:
    let
      resolvedArgs = aspect.__parametricResolvedArgs or [ ];
    in
    (resolvedArgs != [ ] && builtins.any (ak: ctx ? ${ak}) resolvedArgs)
    || (aspect.meta.contextDependent or false);

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
        emitClassEntry {
          class = k;
          identity = if isMulti then "${nodeIdentity}[${toString idx}]" else nodeIdentity;
          inherit
            module
            ctx
            aspectPolicy
            globalPolicy
            ;
          isContextDependent = contextDep;
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
        ctx = ctxFromHandlers (aspect.__scopeHandlers or { });
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
