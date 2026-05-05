# Effect handler: restore-scope
# Restores currentScope to the given parentScope after entity resolution.
{ ... }:
let
  restoreScopeHandler = {
    "restore-scope" =
      { param, state }:
      {
        resume = null;
        state = state // {
          currentScope = param.parentScope;
        };
      };
  };
in
{
  inherit restoreScopeHandler;
}
