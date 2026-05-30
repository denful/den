{ denTest, lib, ... }:
{
  flake.tests.pipes = {
    test-pipe-declaration = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };
        den.aspects.igloo = {
          nixos.networking.hostName = "pipe-test";
        };
        expr = igloo.networking.hostName;
        expected = "pipe-test";
      }
    );

    # Pipe key reaches scopedClassImports, not emitted as class module.
    # If firewall quirk became a NixOS module, NixOS would error on { ports = [...]; }.
    test-pipe-key-not-class = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };
        den.aspects.igloo = {
          nixos.networking.hostName = "pipe-classify";
          firewall = {
            ports = [
              80
              443
            ];
          };
        };
        expr = igloo.networking.hostName;
        expected = "pipe-classify";
      }
    );

    # Firewall aggregation: multiple producers, one consumer on same host.
    test-pipe-local-consumption = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.nginx
            den.aspects.postgres
            den.aspects.networking
          ];
        };

        den.aspects.nginx = {
          nixos.services.nginx.enable = true;
          firewall = {
            ports = [
              80
              443
            ];
          };
        };
        den.aspects.postgres = {
          nixos.services.postgresql.enable = true;
          firewall = {
            ports = [ 5432 ];
          };
        };

        den.aspects.networking = {
          nixos =
            { firewall, lib, ... }:
            {
              networking.firewall.allowedTCPPorts = lib.concatMap (f: f.ports or [ ]) firewall;
            };
        };

        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [
          80
          443
          5432
        ];
      }
    );

    # Empty pipe returns [].
    test-pipe-empty = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };

        den.aspects.igloo = {
          includes = [ den.aspects.networking ];
        };

        den.aspects.networking = {
          nixos =
            { firewall, lib, ... }:
            {
              networking.firewall.allowedTCPPorts = lib.concatMap (f: f.ports or [ ]) firewall;
            };
        };

        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [ ];
      }
    );

    # List-valued quirks are auto-flattened.
    test-pipe-list-flatten = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items = {
          description = "List items";
        };

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          items = [
            { name = "a"; }
            { name = "b"; }
          ];
        };

        den.aspects.consumer = {
          nixos =
            { items, lib, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.name) items;
            };
        };

        expr = igloo.networking.hostName;
        expected = "a-b";
      }
    );

    test-pipe-class-collision = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.nixos = {
          description = "should collide with den.classes.nixos";
        };
        # Accessing den.quirks should trigger the collision assertion.
        expr = !(builtins.tryEval (builtins.deepSeq den.quirks null)).success;
        expected = true;
      }
    );
    # Discriminator deferred until pipe data available: aspect conditionally
    # included based on pipe data.
    test-pipe-discriminator = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };

        den.aspects.igloo = {
          includes = [ den.aspects.firewall-aware ];
          firewall = [
            80
            443
          ];
        };

        # This aspect requires { firewall, ... } — deferred during pipeline walk,
        # resolved post-assembly when pipe data is available.
        den.aspects.firewall-aware = {
          nixos =
            { firewall, ... }:
            {
              networking.hostName = if builtins.length firewall > 1 then "multi-port" else "single-port";
            };
        };

        expr = igloo.networking.hostName;
        expected = "multi-port";
      }
    );

    # Empty pipe discriminator: aspect sees empty list when no pipe data emitted.
    test-pipe-discriminator-empty = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.firewall = {
          description = "Firewall port declarations";
        };

        den.aspects.igloo = {
          includes = [ den.aspects.firewall-aware ];
          # No firewall pipe data emitted.
        };

        den.aspects.firewall-aware = {
          nixos =
            { firewall, ... }:
            {
              networking.hostName = if firewall == [ ] then "no-ports" else "has-ports";
            };
        };

        expr = igloo.networking.hostName;
        expected = "no-ports";
      }
    );

    # Parametric pipe values with unsatisfied required args pass through
    # unresolved instead of crashing (e.g. quirk needing pkgs at a scope
    # without pkgs).
    test-pipe-unsatisfied-parametric-passthrough = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.build-info.description = "Build info requiring system args";

        den.aspects.igloo = {
          includes = [
            den.aspects.producer
            den.aspects.consumer
          ];
        };

        den.aspects.producer = {
          build-info =
            { pkgs, ... }:
            {
              name = pkgs.hello.name;
            };
        };

        den.aspects.consumer = {
          nixos =
            { build-info, ... }:
            {
              networking.hostName =
                if builtins.length build-info == 1 && builtins.isFunction (builtins.head build-info) then
                  "passthrough"
                else
                  "resolved";
            };
        };

        expr = igloo.networking.hostName;
        expected = "passthrough";
      }
    );
  };
}
