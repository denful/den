# A policy declares a directed edge between entity kinds with a
# resolve function that performs fan-out/discrimination.
{ lib, den, ... }:
let
  policyType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "Source entity kind (e.g., 'host')";
      };
      to = lib.mkOption {
        type = lib.types.str;
        description = "Target entity kind or stage name (e.g., 'user', 'hm-host')";
      };
      as = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Context key used for the synthesized output attrset entry.
          Defaults to the `to` value when empty.
          Useful for sibling routing (e.g., host→host where `as = "peer"` avoids collision).
        '';
      };
      resolve = lib.mkOption {
        type = lib.types.raw;
        description = ''
          Function that takes accumulated pipeline context and returns
          a list of target context attrsets.
          Example: { host }: map (user: { inherit host user; }) (lib.attrValues host.users)
        '';
      };
      handlers = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
        description = "Named effect handlers installed when this policy fires.";
      };
      aspects = lib.mkOption {
        type = lib.types.listOf (
          lib.types.coercedTo lib.types.str (name: den.aspects.${name}) den.lib.aspects.types.providerType
        );
        default = [ ];
        description = "Aspects to include for entities resolved by this policy.";
      };
      isolateFanOut = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run each fan-out context in an isolated sub-pipeline instead of shared state.";
      };
      _core = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
        visible = false;
        description = "When true, policy is always active without explicit opt-in.";
      };
    };
  };
  # Dual type: old-style attrsets go through policyType submodule,
  # new-style functions (plain or __functor) pass through as raw.
  dualPolicyType = lib.mkOptionType {
    name = "dualPolicy";
    description = "old-style policy submodule or new-style policy function";
    check = v: builtins.isFunction v || builtins.isAttrs v;
    merge =
      loc: defs:
      let
        val = (builtins.head defs).value;
      in
      if builtins.isFunction val || isFunctorAttrset val then
        # New-style: plain function or __functor attrset — pass through raw
        (lib.types.raw.merge loc defs)
      else
        # Old-style: attrset → evaluate through policyType submodule
        (policyType.merge loc defs);
  };

  # __functor attrsets are callable but builtins.isFunction returns false for them.
  isFunctorAttrset = v: builtins.isAttrs v && v ? __functor;

  # Detection: new-style policies are plain functions or __functor attrsets.
  isNewStylePolicy = policy: builtins.isFunction policy || isFunctorAttrset policy;

  isOldStylePolicy =
    policy: builtins.isAttrs policy && !isFunctorAttrset policy && policy ? from && policy ? resolve;

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
    policyType
    dualPolicyType
    isFunctorAttrset
    isNewStylePolicy
    isOldStylePolicy
    policyFnArgs
    ;
}
