# Regression: two STANDALONE homes sharing a username but bound to different
# hosts (`user@hostA`, `user@hostB`) collapsed onto ONE pipeline scope, so each
# flake output yielded the other's configuration.
#
# `mkScopeId` (nix/lib/aspects/fx/pipeline.nix) rendered an entity as `v.name`,
# but a home's `name` is force-set to the bare user name, so both rendered
# `home=someuser` and shared a scope. Fix: entities expose `__scopeName` (their
# registry key) and mkScopeId reads that, falling back to `name`.
#
# The `provides.<hostname>` cases are downstream symptoms of the same collapse;
# `test-two-targets-single-home` is the control proving the dispatch itself is
# sound. Markers are separate `sessionVariables` keys so a leak surfaces as an
# extra attribute rather than a merge conflict.
{ denTest, ... }:
{
  flake.tests.home-samename-crosshost-scope = {

    # The core defect, with no provides involved: each home must resolve its own
    # host context, not the first-declared home's.
    test-same-username-homes-resolve-independently = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux."someuser@hostA" = { };
        den.homes.x86_64-linux."someuser@hostB" = { };

        den.aspects.someuser.homeManager =
          { home, ... }:
          {
            home = {
              username = "someuser";
              homeDirectory = "/home/someuser";
              sessionVariables.SAW_HOST = home.hostName;
            };
          };

        expr =
          let
            sawHost = key: config.flake.homeConfigurations.${key}.config.home.sessionVariables.SAW_HOST;
          in
          {
            hostA = sawHost "someuser@hostA";
            hostB = sawHost "someuser@hostB";
          };
        expected = {
          hostA = "hostA";
          hostB = "hostB";
        };
      }
    );

    # No `den.hosts` at all: both homes synthesize their host identity from the
    # `user@host` key, so only the home entities are in play.
    test-synthetic-host-provides-no-cross-contamination = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux."someuser@hostA" = { };
        den.homes.x86_64-linux."someuser@hostB" = { };

        den.aspects.someuser.homeManager.home = {
          username = "someuser";
          homeDirectory = "/home/someuser";
        };
        den.aspects.someuser.provides = {
          hostA.homeManager.home.sessionVariables.FROM_A = "a";
          hostB.homeManager.home.sessionVariables.FROM_B = "b";
        };

        expr =
          let
            varsOf = key: config.flake.homeConfigurations.${key}.config.home.sessionVariables;
            a = varsOf "someuser@hostA";
            b = varsOf "someuser@hostB";
          in
          {
            hostA = {
              own = a.FROM_A or "MISSING";
              other = a.FROM_B or "MISSING";
            };
            hostB = {
              own = b.FROM_B or "MISSING";
              other = b.FROM_A or "MISSING";
            };
          };
        expected = {
          hostA = {
            own = "a";
            other = "MISSING";
          };
          hostB = {
            own = "b";
            other = "MISSING";
          };
        };
      }
    );

    # Both hosts declared, each with the same user. The users keep
    # `classes = [ "user" ]` so the hosts do not also build inline home-manager —
    # the standalone homes are the delivery path under test.
    test-declared-host-provides-no-cross-contamination = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.hostA.users.someuser.classes = [ "user" ];
        den.hosts.x86_64-linux.hostB.users.someuser.classes = [ "user" ];

        den.homes.x86_64-linux."someuser@hostA" = { };
        den.homes.x86_64-linux."someuser@hostB" = { };

        den.aspects.someuser.homeManager.home = {
          username = "someuser";
          homeDirectory = "/home/someuser";
        };
        den.aspects.someuser.provides = {
          hostA.homeManager.home.sessionVariables.FROM_A = "a";
          hostB.homeManager.home.sessionVariables.FROM_B = "b";
        };

        expr =
          let
            varsOf = key: config.flake.homeConfigurations.${key}.config.home.sessionVariables;
            a = varsOf "someuser@hostA";
            b = varsOf "someuser@hostB";
          in
          {
            hostA = {
              own = a.FROM_A or "MISSING";
              other = a.FROM_B or "MISSING";
            };
            hostB = {
              own = b.FROM_B or "MISSING";
              other = b.FROM_A or "MISSING";
            };
          };
        expected = {
          hostA = {
            own = "a";
            other = "MISSING";
          };
          hostB = {
            own = "b";
            other = "MISSING";
          };
        };
      }
    );

    # Control: the same two-target aspect with only ONE home consuming it — the
    # `provides.<hostname>` dispatch itself was never the defect.
    test-two-targets-single-home = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux."someuser@hostB" = { };

        den.aspects.someuser.homeManager.home = {
          username = "someuser";
          homeDirectory = "/home/someuser";
        };
        den.aspects.someuser.provides = {
          hostA.homeManager.home.sessionVariables.FROM_A = "a";
          hostB.homeManager.home.sessionVariables.FROM_B = "b";
        };

        expr =
          let
            vars = config.flake.homeConfigurations."someuser@hostB".config.home.sessionVariables;
          in
          {
            own = vars.FROM_B or "MISSING";
            other = vars.FROM_A or "MISSING";
          };
        expected = {
          own = "b";
          other = "MISSING";
        };
      }
    );

  };
}
