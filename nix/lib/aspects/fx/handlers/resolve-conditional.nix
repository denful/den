{
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects.fx.aspect) emitIncludes;

  tombstoneAll =
    aspects:
    builtins.foldl' (
      acc: aspect:
      fx.bind acc (
        results:
        let
          tombstone = identity.tombstone aspect { guardFailed = true; };
        in
        fx.bind (fx.send "resolve-complete" tombstone) (_: fx.pure (results ++ [ tombstone ]))
      )
    ) (fx.pure [ ]) aspects;
in
{
  resolveConditionalHandler = {
    "resolve-conditional" =
      { param, state }:
      let
        condNode = param;
      in
      {
        resume = fx.bind (fx.send "get-path-set" null) (
          pathSet:
          let
            guardCtx = {
              hasAspect = ref: pathSet ? ${identity.key ref};
            };
            pass = condNode.meta.guard guardCtx;
          in
          if pass then
            emitIncludes {
              __parentScopeHandlers = condNode.__scopeHandlers or null;
              __parentCtxId = condNode.__ctxId or null;
            } condNode.meta.aspects
          else
            tombstoneAll condNode.meta.aspects
        );
        inherit state;
      };
  };
}
