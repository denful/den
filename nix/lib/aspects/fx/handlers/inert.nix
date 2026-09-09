# Effect handler: record-inert
# Records bind's misplaced-entity-arg inert verdict into scoped state.
#
# The verdict is silent and correct in the main pipeline — an aspect inert at
# one scope is delivered at another — so nothing reads this there. It exists
# for positions that know they are TERMINAL (resolve.nix's post-assembly
# drain), where there is no later scope and the verdict means the content is
# gone for good. Only bind knows the verdict; only the drain knows it is
# terminal, so each states its own half.
_:
let
  inherit (import ./state-util.nix) scopedAppend;

  recordInertHandler = {
    "record-inert" =
      { param, state }:
      let
        scope = state.currentScope;
      in
      {
        resume = null;
        state = scopedAppend state "scopedInertAspects" scope (param // { sourceScopeId = scope; });
      };
  };
in
{
  inherit recordInertHandler;
}
