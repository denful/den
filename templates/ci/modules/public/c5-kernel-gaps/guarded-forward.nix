{ denTest, ... }:
let
  imperModule =
    { lib, ... }:
    {
      options.impermanence = lib.mkOption {
        type = lib.types.submoduleWith {
          modules = [
            {
              options.foo = lib.mkOption {
                type = lib.types.int;
                default = 0;
              };
            }
          ];
        };
        default = { };
      };
    };
in
{
  flake.tests.guarded-forward = {

    test-guard-applies-when-target-exists = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "imper";
            intoClass = _: "nixos";
            intoPath = _: [ "impermanence" ];
            fromAspect = _: lib.head aspect-chain;
            guard = { options, ... }: options ? impermanence;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [ forwarded ];
          nixos.imports = [ imperModule ];
          imper.foo = 42;
        };

        expr = igloo.impermanence.foo;
        expected = 42;
      }
    );

    test-guard-skips-when-target-missing = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "imper";
            intoClass = _: "nixos";
            intoPath = _: [ "impermanence" ];
            fromAspect = _: lib.head aspect-chain;
            guard = { options, ... }: options ? impermanence;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [ forwarded ];
          imper.foo = 42;
        };

        expr = igloo.networking.hostName;
        expected = "nixos";
      }
    );

    test-guard-can-read-config-values = denTest (
      {
        den,
        lib,
        igloo,
        tuxHm,
        pinguHm,
        ...
      }:
      {

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.schema.user.classes = [ "homeManager" ];

        den.aspects.pingu.homeManager.programs.vim.enable = true;

        den.schema.user.includes =
          let
            unset.homeManager.home.keyboard.model = lib.mkDefault "unset";

            vimer-home =
              { class, aspect-chain }:
              den.provides.forward {
                each = lib.singleton true;
                fromAspect = _: lib.head aspect-chain;
                fromClass = _: "home-pingu";
                intoClass = _: "homeManager";
                intoPath = _: [ "home" ];
                guard = { config, ... }: _: lib.mkIf config.programs.vim.enable;
              };

            doit.home-pingu =
              { pkgs, ... }:
              {
                keyboard.model = lib.getName pkgs.hello;
              };

          in
          [
            unset
            doit
            vimer-home
          ];

        expr = {
          tux = tuxHm.home.keyboard.model;
          pingu = pinguHm.home.keyboard.model;
        };
        expected = {
          tux = "unset";
          pingu = "hello";
        };
      }
    );

  };
}
