# Issue #694 §11a R2: policy.for and policy.when keep their inner policy's
# arguments, so the wrapped policy fires where its own relata are bound.
{ denTest, lib, ... }:
let
  hmUser = {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
  };
in
{
  flake.tests.deadbugs.issue-694-combinators = {

    # policy.for <user> reaches the user for three inner shapes.
    test-for-user-inline-aspect = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      lib.recursiveUpdate hmUser {
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          (den.lib.policy.for config.den.hosts.x86_64-linux.igloo.users.tux {
            homeManager.home.sessionVariables.FOR = "inline";
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.FOR or "<missing>";
        expected = "inline";
      }
    );

    test-for-user-host-policy = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      lib.recursiveUpdate hmUser {
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.host-only =
          { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.FOR = host.name; }) ];
        den.aspects.igloo.includes = [
          (den.lib.policy.for config.den.hosts.x86_64-linux.igloo.users.tux den.policies.host-only)
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.FOR or "<missing>";
        expected = "igloo";
      }
    );

    test-for-user-host-user-policy = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      lib.recursiveUpdate hmUser {
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.both =
          { host, user, ... }:
          [
            (den.lib.policy.include { homeManager.home.sessionVariables.FOR = "${host.name}/${user.name}"; })
          ];
        den.aspects.igloo.includes = [
          (den.lib.policy.for config.den.hosts.x86_64-linux.igloo.users.tux den.policies.both)
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.FOR or "<missing>";
        expected = "igloo/tux";
      }
    );

    # policy.for <tux> does not fire for another user.
    test-for-user-not-other-user = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux.classes = [ "homeManager" ];
          pingu.classes = [ "homeManager" ];
        };
        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          (den.lib.policy.for config.den.hosts.x86_64-linux.igloo.users.tux {
            homeManager.home.sessionVariables.FOR = "tux-only";
          })
        ];
        expr = {
          tux = igloo.home-manager.users.tux.home.sessionVariables.FOR or "<missing>";
          pingu = igloo.home-manager.users.pingu.home.sessionVariables.FOR or "<missing>";
        };
        expected = {
          tux = "tux-only";
          pingu = "<missing>";
        };
      }
    );

    # policy.when wrapping { host, user } on a host lands at the user. On main
    # this throws: the wrapper declared no arguments, fired at the host and
    # called the inner policy without `user`.
    test-when-host-user-on-host = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate hmUser {
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.both =
          { host, user, ... }:
          [ (den.lib.policy.include { homeManager.home.sessionVariables.WHEN = user.name; }) ];
        den.aspects.igloo.includes = [ (den.lib.policy.when ({ host, ... }: true) den.policies.both) ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.WHEN or "<missing>";
        expected = "tux";
      }
    );

    # Both wrappers declare their inner policy's arguments; one required on
    # either side stays required.
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
        whenP = den.lib.policy.when ({ user, ... }: true) inner;
        forP = den.lib.policy.for config.den.hosts.x86_64-linux.igloo.users.tux inner;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = {
          when = lib.functionArgs whenP.fn;
          for = lib.functionArgs forP.fn;
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

    # A wrapped policy passes the late filter (which reads its arguments)
    # without aborting, and fires.
    test-wrapped-policy-passes-late-filter = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.policies.both =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc."w-${user.name}".text = user.name;
            })
          ];
        den.aspects.igloo.includes = [ (den.lib.policy.when ({ host, ... }: true) den.policies.both) ];
        expr = {
          tux = igloo.environment.etc.w-tux.text or "<missing>";
          pingu = igloo.environment.etc.w-pingu.text or "<missing>";
        };
        expected = {
          tux = "tux";
          pingu = "pingu";
        };
      }
    );

    # R2 (gate N8): `provides.<user>` declares only optional entity arguments,
    # and an instance assigns every declared argument the scope binds, so it
    # still lands at the named user.
    test-provides-named-user-lands = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate hmUser {
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.provides.tux.homeManager.home.sessionVariables.NAMED = "igloo-to-tux";
        expr = igloo.home-manager.users.tux.home.sessionVariables.NAMED or "<missing>";
        expected = "igloo-to-tux";
      }
    );
  };
}
