# Policy type utilities — detection and argument extraction.
{ lib, ... }:
let
  # __functor attrsets are callable but builtins.isFunction returns false for them.
  isFunctorAttrset = v: builtins.isAttrs v && v ? __functor;

  # Detection: new-style policies are plain functions or __functor attrsets.
  isNewStylePolicy = policy: builtins.isFunction policy || isFunctorAttrset policy;

  # Extract function args from a policy, handling __functor attrsets correctly.
  # lib.functionArgs on a __functor attrset returns {} (inspects __functionArgs attr).
  # We need to call __functor to get the actual function, then inspect its args.
  policyFnArgs =
    policy:
    if builtins.isAttrs policy && policy ? __functor then
      lib.functionArgs (policy.__functor policy)
    else
      lib.functionArgs policy;
in
{
  inherit
    isFunctorAttrset
    isNewStylePolicy
    policyFnArgs
    ;
}
