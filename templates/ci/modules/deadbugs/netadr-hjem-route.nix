# Regression: a simple `policy.route` into a home-env class (homeManager / hjem)
# was silently dropped.  Home-env classes are consumed by makeHomeEnv's
# `userForward` (a __complexForward routing homeManager -> host.class).  The
# route toposort only treated __complexForward routes as producers, so the
# consuming forward could run BEFORE the simple route injected its content,
# losing it.  Models netadr's hjemLinux -> hjem policy (homeManager == hjem).
{ denTest, ... }:
{
  flake.tests.netadr-hjem-route = {

    # User-scope source, policy fires at user scope (host+user signature).
    test-route-user-scope-usersig = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.srcLinux.description = "Linux source class";

        den.policies.srcLinux-to-hm =
          { host, user, ... }:
          lib.optionals (lib.hasSuffix "-linux" host.system) [
            (den.lib.policy.route {
              fromClass = "srcLinux";
              intoClass = "homeManager";
              path = [ ];
            })
          ];
        den.default.includes = [ den.policies.srcLinux-to-hm ];

        den.aspects.tux.srcLinux.home.sessionVariables.ROUTED = "yes";

        expr = tuxHm.home.sessionVariables.ROUTED or "MISSING";
        expected = "yes";
      }
    );

    # netadr's exact shape: host-signature policy, source on a user self-provide.
    test-route-user-scope-provide = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.srcLinux.description = "Linux source class";

        den.policies.srcLinux-to-hm =
          { host, ... }:
          lib.optionals (lib.hasSuffix "-linux" host.system) [
            (den.lib.policy.route {
              fromClass = "srcLinux";
              intoClass = "homeManager";
              path = [ ];
            })
          ];
        den.default.includes = [ den.policies.srcLinux-to-hm ];

        den.aspects.tux = {
          includes = [ den.aspects.tux._.prog ];
          _.prog.srcLinux.home.sessionVariables.ROUTED = "yes";
        };

        expr = tuxHm.home.sessionVariables.ROUTED or "MISSING";
        expected = "yes";
      }
    );

    # Different resolving scope: a standalone home entity (den.homes), which
    # resolves at the `home` scope and is assembled via its own instantiate
    # (not the user-scope userForward).  Confirms route -> homeManager is not
    # user-scope-specific.
    test-route-standalone-home-scope = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        den.classes.srcLinux.description = "Linux source class";

        den.policies.srcLinux-to-hm =
          { home, ... }:
          [
            (den.lib.policy.route {
              fromClass = "srcLinux";
              intoClass = "homeManager";
              path = [ ];
            })
          ];
        den.default.includes = [
          den.provides.define-user
          den.policies.srcLinux-to-hm
        ];

        den.aspects.tux.srcLinux.home.sessionVariables.ROUTED = "yes";

        expr = config.flake.homeConfigurations.tux.config.home.sessionVariables.ROUTED or "MISSING";
        expected = "yes";
      }
    );
  };
}
