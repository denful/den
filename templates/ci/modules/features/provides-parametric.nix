{ denTest, inputs, ... }:
{

  flake.tests.provides-parametric = {

    test-parametric-inside-provides = denTest (
      {
        den,
        ns,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [ (inputs.den.namespace "ns" false) ];

        ns.foo = den.lib.parametric { };
        ns.bar.provides.baz = den.lib.parametric { };
        ns.a = den.lib.parametric {
          provides.b = den.lib.parametric { };
          provides.c = den.lib.parametric { };
          provides.d = den.lib.parametric {
            provides.e = den.lib.parametric { nixos.networking.hostName = "pinguino"; };
          };
        };

        den.aspects.igloo.includes = [
          ns.foo
          ns.bar.provides.baz
          ns.a
          ns.a.provides.b
          ns.a.provides.c
          ns.a.provides.d
          ns.a.provides.d.provides.e
        ];

        expr = igloo.networking.hostName;
        expected = "pinguino";
      }
    );

  };

  # Bare function sub-aspects receive parametric context from parent.
  flake.tests.provides-parametric-bare-fn = {

    test-bare-fn-sub-aspect-receives-host = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.monitoring =
              { host, ... }:
              {
                includes = [ den.aspects.monitoring.provides.node-exporter ];
              };
          }
          {
            den.aspects.monitoring.provides.node-exporter =
              { host, ... }:
              {
                nixos.networking.hostName = "${host.name}-monitored";
              };
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.monitoring ];

        expr = igloo.networking.hostName;
        expected = "igloo-monitored";
      }
    );

    # Regression: provides.to-hosts compat shim uses policy.provide (no duplicate emissions).
    test-provides-to-hosts-compat-no-dupes = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.shared-host-config = {
          provides.to-hosts.nixos.networking.hostName = "via-compat";
        };

        den.aspects.igloo.includes = [ den.aspects.shared-host-config ];

        expr = igloo.networking.hostName;
        expected = "via-compat";
      }
    );

    # Regression: provides.to-users compat shim uses policy.provide (content reaches HM).
    test-provides-to-users-via-provide = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.shared-user-config = {
          provides.to-users = _: {
            homeManager = _: {
              programs.direnv.enable = true;
            };
          };
        };

        den.aspects.igloo.includes = [ den.aspects.shared-user-config ];

        expr = tuxHm.programs.direnv.enable;
        expected = true;
      }
    );

    # Regression: provides.to-users with includes pattern (drupol stateVersion bug).
    # The value is { includes = [ base ]; } where base has homeManager class keys.
    # The compat shim must walk includes to extract class modules.
    test-provides-to-users-includes = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.base.homeManager.home.stateVersion = "26.05";

        den.aspects.shared-config = {
          provides.to-users.includes = [ den.aspects.base ];
        };

        den.aspects.igloo.includes = [ den.aspects.shared-config ];

        expr = tuxHm.home.stateVersion;
        expected = "26.05";
      }
    );

    test-static-parent-bare-fn-sub = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.monitoring.includes = [ den.aspects.monitoring.provides.agent ];
          }
          {
            den.aspects.monitoring.provides.agent =
              { host, ... }:
              {
                nixos.networking.hostName = "${host.name}-agent";
              };
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.monitoring ];

        expr = igloo.networking.hostName;
        expected = "igloo-agent";
      }
    );
  };

}
