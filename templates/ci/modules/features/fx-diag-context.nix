# Tests for the diag library's context graph construction.
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-diag-context = {

    test-host-context = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.testhost.users.tux = { };
        den.aspects.testhost.nixos =
          { ... }:
          {
            networking.hostName = "fx-diag-test";
          };
        expr =
          let
            host = lib.head (builtins.attrValues den.hosts.x86_64-linux);
            graph = den.lib.diag.hostContext { inherit host; };
          in
          {
            hasNodes = (graph.nodes or [ ]) != [ ];
            hasEdges = graph ? edges;
            rootName = graph.rootName or "unknown";
          };
        expected = {
          hasNodes = true;
          hasEdges = true;
          rootName = "testhost";
        };
      }
    );

    test-capture-in-context = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.testhost.users.tux = { };
        den.aspects.testhost.nixos =
          { ... }:
          {
            networking.hostName = "test";
          };
        den.aspects.testhost.includes = [
          den.aspects.networking
        ];
        den.aspects.networking.nixos =
          { ... }:
          {
            networking.firewall.enable = true;
          };
        expr =
          let
            host = lib.head (builtins.attrValues den.hosts.x86_64-linux);
            root = den.lib.resolveEntity "host" { inherit host; };
            result = den.lib.diag.captureWithPaths [ "nixos" ] root;
          in
          {
            hasEntries = (builtins.length result.entries) > 0;
            hasPathsByClass = result.pathsByClass ? nixos;
          };
        expected = {
          hasEntries = true;
          hasPathsByClass = true;
        };
      }
    );

    test-handleWith-exclude-in-aspect = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.testhost.users.tux = { };
        den.aspects.testhost = {
          includes = [
            den.aspects.networking
            den.aspects.desktop
          ];
          meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.tailscale;
        };
        den.aspects.networking.nixos =
          { ... }:
          {
            networking.firewall.enable = true;
          };
        den.aspects.desktop.nixos =
          { ... }:
          {
            services.xserver.enable = true;
          };
        den.aspects.tailscale.nixos =
          { ... }:
          {
            services.tailscale.enable = true;
          };
        expr =
          let
            host = lib.head (builtins.attrValues den.hosts.x86_64-linux);
            graph = den.lib.diag.hostContext { inherit host; };
          in
          {
            hasNodes = (graph.nodes or [ ]) != [ ];
          };
        expected = {
          hasNodes = true;
        };
      }
    );

    test-fx-constraints-access = denTest (
      { den, ... }:
      let
        excludeDecl = den.lib.aspects.fx.constraints.exclude {
          name = "drop";
          meta.provider = [ ];
        };
      in
      {
        expr = excludeDecl.type;
        expected = "exclude";
      }
    );

  };
}
