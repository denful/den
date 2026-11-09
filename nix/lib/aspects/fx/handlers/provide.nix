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
        # Stood down because a transition default already carries its content
        # (#694): never delivered, only read by the migration warning.
        state = scopedAppend state (
          if param.__standDown or false then "scopedStandDownProvides" else "scopedProvides"
        ) scope (param // { sourceScopeId = scope; });
      };
  };
in
{
  inherit provideHandler;
}
