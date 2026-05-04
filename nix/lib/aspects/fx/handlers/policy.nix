# Effect handler: register-aspect-policy
# Registers policies declared on aspects into scope-partitioned state.
_:
let
  inherit (import ./state-util.nix) scopedMerge;

  registerAspectPolicyHandler = {
    "register-aspect-policy" =
      { param, state }:
      let
        entry = {
          inherit (param) fn ownerIdentity;
        };
      in
      {
        resume = null;
        state =
          (scopedMerge state "scopedAspectPolicies" state.currentScope {
            ${param.name} = entry;
          })
          // {
            flatAspectPolicies = (state.flatAspectPolicies or { }) // {
              ${param.name} = entry;
            };
          };
      };
  };
in
{
  inherit registerAspectPolicyHandler;
}
