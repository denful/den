# Effect handlers: defer-include, drain-deferred
# Manages deferred includes that wait for required context args.
{ lib, ... }:
let
  inherit (import ./state-util.nix) scopedAppend;

  deferredIncludeHandler = {
    "defer-include" =
      { param, state }:
      {
        resume = [ ];
        state = scopedAppend state "scopedDeferredIncludes" state.currentScope param;
      };
  };

  drainDeferredHandler = {
    "drain-deferred" =
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
in
{
  inherit deferredIncludeHandler drainDeferredHandler;
}
