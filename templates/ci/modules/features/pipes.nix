{ denTest, lib, ... }:
{
  flake.tests.pipes = {
    test-pipe-declaration = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.firewall = {
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
        den.pipes.firewall = {
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
        den.pipes.firewall = {
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
        den.pipes.firewall = {
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
        den.pipes.items = {
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
        den.pipes.nixos = {
          description = "should collide with den.classes.nixos";
        };
        # Accessing den.pipes should trigger the collision assertion.
        expr = !(builtins.tryEval (builtins.deepSeq den.pipes null)).success;
        expected = true;
      }
    );
  };
}
