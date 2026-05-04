# Handles: drain
# Partitions deferred includes by ctx satisfiability.
{ lib, ... }:
{
  drainHandler = {
    "drain" =
      { param, state }:
      let
        ctx = param;
        inherit (state) currentScope;
        allScoped = (state.scopedDeferredIncludes or (_: { })) null;
        scopeDeferred = allScoped.${currentScope} or [ ];
      in
      if scopeDeferred == [ ] then
        {
          resume = [ ];
          inherit state;
        }
      else
        let
          partitioned = lib.partition (
            d: builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs
          ) scopeDeferred;
          satisfiable = partitioned.right;
          remaining = partitioned.wrong;
        in
        {
          resume = satisfiable;
          state = state // {
            scopedDeferredIncludes =
              _:
              allScoped
              // {
                ${currentScope} = remaining;
              };
          };
        };
  };
}
