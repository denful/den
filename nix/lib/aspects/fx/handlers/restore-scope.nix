# Effect handler: restore-scope
# Restores currentScope to the given parentScope after entity resolution.
{ lib, ... }:
let
  restoreScopeHandler = {
    "restore-scope" =
      { param, state }:
      let
        stack = state.inLateDispatchStack or [ ];
        prevLateDispatch = if stack == [ ] then false else lib.last stack;
        newStack = if stack == [ ] then [ ] else lib.init stack;
      in
      {
        resume = null;
        state = state // {
          currentScope = param.parentScope;
          # Restore parent's inLateDispatch value — each scope level has
          # its own late-dispatch tracking independent of children.
          inLateDispatch = prevLateDispatch;
          inLateDispatchStack = newStack;
        };
      };
  };
in
{
  inherit restoreScopeHandler;
}
