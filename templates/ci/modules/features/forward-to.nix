{ denTest, lib, ... }:
{
  flake.tests.forward-to = {

    test-forwardTo-default-routing = denTest (
      { den, igloo, ... }:
      let
        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "custom";
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.custom = {
          description = "Custom class with forwardTo";
          forwardTo = {
            class = "nixos";
            path = [ ];
          };
        };

        den.aspects.igloo = {
          includes = [ forwarded ];
          custom.networking.hostName = "from-forwardTo";
        };

        expr = igloo.networking.hostName;
        expected = "from-forwardTo";
      }
    );

    test-forwardTo-with-path = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        fwdModule = {
          options.items = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };

        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "src";
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.src = {
          description = "Source class with path";
          forwardTo = {
            class = "nixos";
            path = [ "fwd-box" ];
          };
        };

        den.aspects.igloo = {
          includes = [ forwarded ];
          nixos.imports = [
            {
              options.fwd-box = lib.mkOption {
                type = lib.types.submoduleWith { modules = [ fwdModule ]; };
              };
            }
          ];
          nixos.fwd-box.items = [ "direct" ];
          src.items = [ "forwarded" ];
        };

        expr = lib.sort (a: b: a < b) igloo.fwd-box.items;
        expected = [
          "direct"
          "forwarded"
        ];
      }
    );

    test-explicit-intoClass-overrides-forwardTo = denTest (
      { den, igloo, ... }:
      let
        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "custom";
            intoClass = _: "nixos";
            intoPath = _: [ ];
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.custom = {
          description = "Custom class";
          forwardTo = {
            class = "homeManager";
            path = [
              "somewhere"
              "else"
            ];
          };
        };

        den.aspects.igloo = {
          includes = [ forwarded ];
          custom.networking.hostName = "explicit-override";
        };

        expr = igloo.networking.hostName;
        expected = "explicit-override";
      }
    );

    test-forwardTo-null-requires-explicit = denTest (
      { den, igloo, ... }:
      let
        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "noroute";
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.noroute = {
          description = "No routing";
        };

        den.aspects.igloo = {
          includes = [ forwarded ];
          noroute.something = "value";
        };

        expr = igloo ? networking;
        expectedError = {
          type = "ThrownError";
          msg = "forward: no intoClass for fromClass=noroute";
        };
      }
    );

  };
}
