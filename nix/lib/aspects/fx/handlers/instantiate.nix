# Effect handler: register-instantiate
# Registers instantiation specs for post-pipeline entity creation.
_:
let
  inherit (import ./state-util.nix) scopedAppend;

  registerInstantiateHandler = {
    "register-instantiate" =
      { param, state }:
      let
        scope = state.currentScope;
      in
      {
        resume = null;
        state = scopedAppend state "scopedInstantiates" scope (param // { sourceScopeId = scope; });
      };
  };
in
{
  inherit registerInstantiateHandler;
}
