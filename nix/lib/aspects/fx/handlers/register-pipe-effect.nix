# Effect handler: register-pipe-effect
# Collects pipe effects into scopedPipeEffects.
_:
let
  inherit (import ./state-util.nix) scopedAppend;

  registerPipeEffectHandler = {
    "register-pipe-effect" =
      { param, state }:
      let
        scope = state.currentScope;
      in
      {
        resume = null;
        state = scopedAppend state "scopedPipeEffects" scope (param // { sourceScopeId = scope; });
      };
  };
in
{
  inherit registerPipeEffectHandler;
}
