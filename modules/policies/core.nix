# Core entity policies — fundamental traversal between entity kinds.
#
# host-to-users uses resolve.shared for shared fan-out.
# Entity-named nested keys on aspects (e.g., den.aspects.igloo.tux where
# tux is a user) are included in the target entity scope automatically.
# *-to-default policies eliminated — den.default is now injected as a
# schema include for host/user/home entity kinds (defaults.nix).
{ lib, den, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  # Host → users: fan-out to each declared user. A host aspect's key named
  # after a user (`den.aspects.<host>.<user>`) is part of that user's own
  # aspect (entities/host.nix), so it reaches only that user.
  den.policies.host-to-users =
    {
      host,
      ...
    }:
    map (user: resolve.shared { inherit user; }) (lib.attrValues host.users);

  den.schema.host.includes = [ den.policies.host-to-users ];
}
