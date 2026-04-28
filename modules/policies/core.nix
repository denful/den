# Core entity policies — fundamental traversal between entity kinds.
#
# All policies retain `from` for entity-kind scoping (policyEffectNamesFor
# filters by from). *-to-default also retains `to` and `__functor` —
# default routing requires transition-based scope isolation.
# host-to-users uses resolve.shared for shared fan-out.
# _core removed — new-style handler skips activation check.
{ lib, den, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  den.policies = {
    host-to-users = {
      from = "host";
      __functor =
        _: { host, ... }: map (user: resolve.shared { inherit user; }) (lib.attrValues host.users);
    };

    host-to-default = {
      from = "host";
      to = "default";
      __functor = _: ctx: [ (resolve ctx) ];
    };

    user-to-default = {
      from = "user";
      to = "default";
      __functor = _: ctx: [ (resolve ctx) ];
    };

    home-to-default = {
      from = "home";
      to = "default";
      __functor = _: ctx: [ (resolve ctx) ];
    };
  };
}
