# policy.for and policy.when keep the wrapped policy's declared arguments, so
# the wrapped policy fires where its own arguments are bound. Late dispatch
# reads a policy's arguments to decide where it fires; a wrapper that declared
# none looked like a policy with no arguments.
{ denTest, lib, ... }:
let
  hmUser = {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
  };
in
{
  flake.tests.deadbugs.policy-combinator-args = {

    # policy.for <user> on a host's includes reaches that user.
    test-for-user-reaches-user = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      lib.recursiveUpdate hmUser {
        den.aspects.igloo.includes = [
          (den.lib.policy.for config.den.hosts.x86_64-linux.igloo.users.tux {
            homeManager.home.sessionVariables.FOR = "tux";
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.FOR or "<missing>";
        expected = "tux";
      }
    );

    # policy.when wrapping a `{ host, user }` policy on a host fires at the
    # user. Calling the inner policy at the host, where `user` is not bound,
    # threw.
    test-when-host-user-on-host = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate hmUser {
        den.policies.both =
          { host, user, ... }:
          [ (den.lib.policy.include { homeManager.home.sessionVariables.WHEN = user.name; }) ];
        den.aspects.igloo.includes = [ (den.lib.policy.when ({ host, ... }: true) den.policies.both) ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.WHEN or "<missing>";
        expected = "tux";
      }
    );

    # An argument either side requires stays required.
    test-wrappers-declare-inner-args = denTest (
      { den, config, ... }:
      let
        inner = {
          __isPolicy = true;
          name = "inner";
          fn =
            {
              host,
              user ? null,
              ...
            }:
            [ ];
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = {
          when = lib.functionArgs (den.lib.policy.when ({ user, ... }: true) inner).fn;
          for = lib.functionArgs (den.lib.policy.for config.den.hosts.x86_64-linux.igloo.users.tux inner).fn;
        };
        expected = {
          when = {
            host = false;
            user = false;
          };
          for = {
            host = false;
            user = false;
          };
        };
      }
    );
  };
}
