{
  denTest,
  ...
}:
{
  flake.tests.nested-provides-forwarding = {

    # Provides children are forwarded onto nested aspects
    test-nested-provides-access = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.group.sub = {
          provides.monitoring.nixos.services.prometheus.enable = true;
        };

        # monitoring should be accessible directly on sub
        den.aspects.igloo.includes = [
          den.aspects.group.sub.monitoring
        ];

        expr = igloo.services.prometheus.enable;
        expected = true;
      }
    );

    # Self-provide still works on nested aspects
    test-nested-self-provide = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.group.sub = {
          provides.sub.nixos.services.openssh.enable = true;
          nixos.networking.hostName = "sub-host";
        };

        den.aspects.igloo.includes = [ den.aspects.group.sub ];

        expr = {
          hostName = igloo.networking.hostName;
          ssh = igloo.services.openssh.enable;
        };
        expected = {
          hostName = "sub-host";
          ssh = true;
        };
      }
    );

    # Direct freeform keys override forwarded provides children
    test-nested-provides-direct-wins = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.group.sub = {
          provides.svc.nixos.networking.hostName = "from-provides";
          svc.nixos.networking.hostName = "from-direct";
        };

        den.aspects.igloo.includes = [ den.aspects.group.sub.svc ];

        expr = igloo.networking.hostName;
        expected = "from-direct";
      }
    );

    # Provides forwarding with multiple children
    test-nested-provides-multiple = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.group.sub = {
          provides.monitoring.nixos.services.prometheus.enable = true;
          provides.logging.nixos.services.journald.forwardToSyslog = true;
        };

        den.aspects.igloo.includes = [
          den.aspects.group.sub.monitoring
          den.aspects.group.sub.logging
        ];

        expr = {
          prom = igloo.services.prometheus.enable;
          journal = igloo.services.journald.forwardToSyslog;
        };
        expected = {
          prom = true;
          journal = true;
        };
      }
    );

    # `_` is documented as an alias for `provides`. aspectSubmodule wires it via
    # mkAliasOptionModule, which a nested key never reaches — writes through it
    # used to land on a structural key the content wrapper then overwrote.
    test-underscore-write-alias-on-nested-aspect = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.alpha ];

        den.aspects.alpha = {
          includes = [ den.aspects.alpha.tools ];
          tools._.to-users.homeManager.home.sessionVariables.ALPHA = "yes";
        };

        expr = tuxHm.home.sessionVariables.ALPHA or "<missing>";
        expected = "yes";
      }
    );

    # The written value reads back through `_` as well as through `provides`,
    # matching how a root aspect publishes both.
    test-underscore-reads-back-on-nested-aspect = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.alpha.tools._.shared ];

        den.aspects.alpha.tools._.shared.nixos.environment.etc."shared".text = "yes";

        expr = den.aspects.alpha.tools.provides ? shared;
        expected = true;
      }
    );

    # `_` called as the all-children shorthand still works alongside the alias.
    test-underscore-shorthand-still-collects-children = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ (den.aspects.alpha.tools._ { }) ];

        den.aspects.alpha.tools = {
          one.nixos.environment.etc."one".text = "yes";
          two.nixos.environment.etc."two".text = "yes";
        };

        expr = {
          one = igloo.environment.etc ? "one";
          two = igloo.environment.etc ? "two";
        };
        expected = {
          one = true;
          two = true;
        };
      }
    );
  };
}
