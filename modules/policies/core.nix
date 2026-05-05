# Core entity policies — fundamental traversal between entity kinds.
#
# host-to-users uses resolve.shared for shared fan-out.
# *-to-default policies eliminated — den.default is now injected as a
# schema include for host/user/home entity kinds (defaults.nix).
{ lib, den, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  den.policies.host-to-users =
    {
      host,
      ...
    }:
    map (user: resolve.shared { inherit user; }) (lib.attrValues host.users);

  den.schema.host.includes = [ den.policies.host-to-users ];
}
