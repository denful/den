{ denTest, ... }:
{
  flake.tests.dynamic-intopath = {

    test-dynamic-intoPath-host-scope = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        slotMod =
          { lib, ... }:
          {
            options.my-slot = lib.mkOption {
              type = lib.types.str;
              default = "slot-a";
            };
            options.my-box = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submoduleWith {
                  modules = [
                    {
                      config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything;
                    }
                  ];
                }
              );
              default = { };
            };
          };

        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "src";
            intoClass = _: "nixos";
            intoPath =
              _:
              { config, ... }:
              [
                "my-box"
                config.my-slot
              ];
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [ forwarded ];
          nixos.imports = [ slotMod ];
          nixos.my-slot = "slot-b";
          src.my-data = "hello-from-src";
        };

        expr = igloo.my-box.slot-b.my-data;
        expected = "hello-from-src";
      }
    );

    test-dynamic-intoPath-user-scope = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        slotMod =
          { lib, ... }:
          {
            options.my-slot = lib.mkOption {
              type = lib.types.str;
              default = "slot-a";
            };
            options.my-box = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submoduleWith {
                  modules = [
                    {
                      config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything;
                    }
                  ];
                }
              );
              default = { };
            };
          };

        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "src";
            intoClass = _: "homeManager";
            intoPath =
              _:
              { config, ... }:
              [
                "my-box"
                config.my-slot
              ];
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.homeManager.home.stateVersion = "25.11";
        den.aspects.tux = {
          includes = [ forwarded ];
          homeManager.imports = [ slotMod ];
          homeManager.my-slot = "slot-b";
          src.my-data = "hello-from-src";
        };

        expr = igloo.home-manager.users.tux.my-box.slot-b.my-data;
        expected = "hello-from-src";
      }
    );

  };
}
