# Core entity policies — fundamental traversal between entity kinds.
#
# All policies use new-style __functor shape with typed effects.
# *-to-default policies pass context through with explicit `to = "default"`.
{ lib, den, ... }:
{
  den.policies = {
    host-to-users = {
      _core = true;
      from = "host";
      isolateFanOut = false;
      __functor =
        _: { host, ... }: map (user: den.lib.policy.resolve { inherit user; }) (lib.attrValues host.users);
    };
    host-to-default = {
      _core = true;
      from = "host";
      to = "default";
      __functor = _: ctx: [ (den.lib.policy.resolve ctx) ];
    };
    user-to-default = {
      _core = true;
      from = "user";
      to = "default";
      __functor = _: ctx: [ (den.lib.policy.resolve ctx) ];
    };
    home-to-default = {
      _core = true;
      from = "home";
      to = "default";
      __functor = _: ctx: [ (den.lib.policy.resolve ctx) ];
    };
  };
}
