# A policy declares a directed edge between entity kinds with a
# resolve function that performs fan-out/discrimination.
{ lib, ... }:
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
      _core = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
        visible = false;
        description = "When true, policy is always active without explicit opt-in.";
      };
    };
  };
in
{
  inherit policyType;
}
