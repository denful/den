_:
let
  inherit (import ./state-util.nix) scopedAppend;

  provideHandler = {
    "register-provide" =
      { param, state }:
      let
        scope = state.currentScope;
      in
      {
        resume = null;
        state = scopedAppend state "scopedProvides" scope (param // { sourceScopeId = scope; });
      };
  };
in
{
  inherit provideHandler;
}
