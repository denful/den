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
        allScoped = (state.scopedDeferredIncludes or (_: { })) null;
        allDeferred = lib.concatLists (lib.attrValues allScoped);
      in
      if allDeferred == [ ] then
        {
          resume = [ ];
          inherit state;
        }
      else
        let
          partitioned = lib.partition (
            d: builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs
          ) allDeferred;
          satisfiable = partitioned.right;
          remaining = partitioned.wrong;
          inherit (state) currentScope;
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
