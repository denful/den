# Tests for policy.provide — direct module delivery into target classes.
{ denTest, lib, ... }:
let
  mkListSubmodule =
    name:
    { lib, ... }:
    {
      options.${name} = lib.mkOption {
        type = lib.types.submoduleWith {
          modules = [
            {
              options.items = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            }
          ];
        };
        default = { };
      };
    };
in
{
  flake.tests.provide = {

    # Direct provide — inject a module into the host's NixOS class.
    test-provide-direct = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.provide-direct =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module = {
                networking.hostName = "provided-host";
              };
            })
          ];

        den.default.includes = [ den.policies.provide-direct ];

        den.aspects.igloo = { };

        expr = igloo.networking.hostName;
        expected = "provided-host";
      }
    );

    # Provide with path — module nested at a submodule path.
    test-provide-with-path = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.provide-with-path =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.items = [ "from-provide" ];
              path = [ "provide-box" ];
            })
          ];

        den.default.includes = [ den.policies.provide-with-path ];

        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "provide-box") ];
          nixos.provide-box.items = [ "from-aspect" ];
        };

        expr = lib.sort (a: b: a < b) igloo.provide-box.items;
        expected = [
          "from-aspect"
          "from-provide"
        ];
      }
    );

    # Provide alongside route — both mechanisms compose.
    test-provide-with-route = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.extra.description = "Extra source class";

        den.policies.provide-and-route =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.items = [ "from-provide" ];
              path = [ "combo-box" ];
            })
            (den.lib.policy.route {
              fromClass = "extra";
              intoClass = host.class;
              path = [ "combo-box" ];
            })
          ];

        den.default.includes = [ den.policies.provide-and-route ];

        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "combo-box") ];
          nixos.combo-box.items = [ "from-aspect" ];
          extra.items = [ "from-route" ];
        };

        expr = lib.sort (a: b: a < b) igloo.combo-box.items;
        expected = [
          "from-aspect"
          "from-provide"
          "from-route"
        ];
      }
    );

    # Cross-class provide — inject homeManager content from a host pipeline policy.
    test-provide-cross-class = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = { };

        den.policies.user-routing =
          { host, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          map (user: resolve { inherit user; }) (builtins.attrValues host.users)
          ++ [
            (include den.policies.provide-cross-class)
          ];

        den.policies.provide-cross-class =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "homeManager";
              module = {
                programs.direnv.enable = true;
              };
            })
          ];

        den.default.includes = [ den.policies.user-routing ];

        expr = tuxHm.programs.direnv.enable;
        expected = true;
      }
    );

  };
}
