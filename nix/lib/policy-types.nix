# Policy type utilities — argument extraction.
{ lib, ... }:
let
  # Extract function args from a policy (always a plain function now).
  policyFnArgs = policy: lib.functionArgs policy;
in
{
  inherit policyFnArgs;
}
