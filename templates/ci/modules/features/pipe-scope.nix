# Tests for pipe.expose — upward scope flow from child to parent.
{ denTest, lib, ... }:
{
  flake.tests.pipe-scope = {

    # User pipe data exposed to host scope via pipe.expose.
    test-pipe-expose-basic = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.prefs = {
          description = "User preferences";
        };

        # User aspect produces pipe data.
        den.aspects.tux = {
          prefs = [
            { editor = "vim"; }
          ];
        };

        # Host aspect consumes pipe data (should see exposed user data).
        den.aspects.igloo = {
          includes = [ den.aspects.host-consumer ];
        };

        den.aspects.host-consumer = {
          nixos =
            { prefs, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (p: p.editor) prefs;
            };
        };

        den.policies.expose-prefs =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "prefs" [
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-prefs ];

        expr = igloo.networking.hostName;
        expected = "vim";
      }
    );

    # Transform stages applied before expose.
    test-pipe-expose-with-transform = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.items = {
          description = "Items";
        };

        den.aspects.tux = {
          items = [
            {
              name = "a";
              keep = true;
            }
            {
              name = "b";
              keep = false;
            }
          ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.item-consumer ];
        };

        den.aspects.item-consumer = {
          nixos =
            { items, ... }:
            {
              networking.hostName = lib.concatMapStringsSep "-" (i: i.label) items;
            };
        };

        den.policies.expose-filtered =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "items" [
              (pipe.filter (i: i.keep))
              (pipe.transform (i: {
                label = "x-${i.name}";
              }))
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-filtered ];

        # Only kept items, transformed, reach the host.
        expr = igloo.networking.hostName;
        expected = "x-a";
      }
    );

    # Exposed data merges with host-local pipe data.
    test-pipe-expose-with-local = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.ports = {
          description = "Port declarations";
        };

        # User aspect produces user-level ports.
        den.aspects.tux = {
          ports = [ 8080 ];
        };

        # Host aspect produces host-level ports AND consumes.
        den.aspects.igloo = {
          includes = [ den.aspects.port-consumer ];
          ports = [ 80 ];
        };

        den.aspects.port-consumer = {
          nixos =
            { ports, lib, ... }:
            {
              networking.firewall.allowedTCPPorts = lib.sort (a: b: a < b) ports;
            };
        };

        den.policies.expose-ports =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "ports" [
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-ports ];

        # Host consumer sees both host-local (80) and exposed user (8080).
        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [
          80
          8080
        ];
      }
    );

    # Exposed data from multiple users merges in host scope.
    test-pipe-expose-multi-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          users.pingu = { };
        };
        den.pipes.shells = {
          description = "Shell preferences";
        };

        den.aspects.tux = {
          shells = [ "zsh" ];
        };
        den.aspects.pingu = {
          shells = [ "fish" ];
        };

        den.aspects.igloo = {
          includes = [ den.aspects.shell-consumer ];
        };

        den.aspects.shell-consumer = {
          nixos =
            { shells, lib, ... }:
            {
              networking.hostName = lib.concatStringsSep "-" (lib.sort (a: b: a < b) shells);
            };
        };

        den.policies.expose-shells =
          { host, user, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [
            (pipe.from "shells" [
              pipe.expose
            ])
          ];

        den.default.includes = [ den.policies.expose-shells ];

        # Host sees shells from both users.
        expr = igloo.networking.hostName;
        expected = "fish-zsh";
      }
    );
  };
}
