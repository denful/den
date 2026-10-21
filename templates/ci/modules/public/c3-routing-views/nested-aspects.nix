{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.nested-aspects = {

    # Direct nesting: igloo.tux = { homeManager... } — activated by policy
    # because tux is a declared user of igloo, not by auto-walk
    test-direct-nesting-basic = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.tux = {
          homeManager.programs.git.enable = true;
        };
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = tuxHm.programs.git.enable;
        expected = true;
      }
    );

    # Direct nesting with nixos class key — requires explicit include
    test-direct-nesting-nixos = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          includes = [ den.aspects.igloo.servers ];
          servers.nixos.networking.hostName = "nested-test";
        };

        expr = igloo.networking.hostName;
        expected = "nested-test";
      }
    );

    # Multi-level nesting — each level requires explicit include
    test-multi-level-nesting = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          includes = [ den.aspects.igloo.development ];
          development = {
            includes = [ den.aspects.igloo.development.gui ];
            gui.nixos.networking.hostName = "multilevel";
          };
        };

        expr = igloo.networking.hostName;
        expected = "multilevel";
      }
    );

    # Nested sub-aspect on parametric parent — defined in separate module
    test-nested-scope-propagation = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        imports = [
          {
            den.aspects.web =
              { host, ... }:
              {
                nixos.networking.hostName = host.name;
              };
          }
          { den.aspects.web.servers.nixos.services.nginx.enable = true; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.web
          den.aspects.web.servers
        ];

        expr = {
          hostName = igloo.networking.hostName;
          hasNginx = igloo.services.nginx.enable;
        };
        expected = {
          hostName = "igloo";
          hasNginx = true;
        };
      }
    );

    # provides still works (backward compat) — self-provide pattern
    test-provides-backward-compat = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.provides.igloo = {
          nixos.networking.hostName = "provides-compat";
        };

        expr = igloo.networking.hostName;
        expected = "provides-compat";
      }
    );

    # Nested sub-aspect on parametric parent — defined in separate module
    test-nested-parametric-parent = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        imports = [
          {
            den.aspects.monitoring =
              { host, ... }:
              {
                nixos.networking.hostName = "${host.name}-monitored";
              };
          }
          { den.aspects.monitoring.agents.nixos.environment.variables.MONITORED = "yes"; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.monitoring
          den.aspects.monitoring.agents
        ];

        expr = {
          hostName = igloo.networking.hostName;
          hasMonitored = igloo.environment.variables ? MONITORED;
        };
        expected = {
          hostName = "igloo-monitored";
          hasMonitored = true;
        };
      }
    );

  };
}
