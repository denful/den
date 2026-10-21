{ denTest, ... }:
{
  flake.tests.forward-alias-class = {

    test-home-alias-forwards-into-home-manager-root = denTest (
      {
        den,
        lib,
        igloo,
        tuxHm,
        ...
      }:
      let
        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.singleton class;
            fromClass = _: "home";
            intoClass = _: "homeManager";
            intoPath = _: [ ];
            fromAspect = _: lib.head aspect-chain;
            guard = { pkgs, ... }: true;
            adaptArgs =
              { osConfig, ... }:
              {
                inherit osConfig;
              };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos.networking.hostName = "storm";

        den.aspects.tux = {
          includes = [
            forwarded
            den.aspects.foo
          ];
        };

        den.aspects.foo.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.bar.home =
          { osConfig, pkgs, ... }:
          {
            programs.fish.enable = true;
            home.keyboard.model = osConfig.networking.hostName;
            home.packages = [ pkgs.hello ];
          };

        den.aspects.baz.home =
          { pkgs, ... }:
          {
            home.packages = [ pkgs.direnv ];
          };

        expr = {
          enable = tuxHm.programs.fish.enable;
          model = tuxHm.home.keyboard.model;
          hello = lib.any (p: "hello" == lib.getName p) tuxHm.home.packages;
          direnv = lib.any (p: "direnv" == lib.getName p) tuxHm.home.packages;
        };
        expected = {
          enable = true;
          model = "storm";
          hello = true;
          direnv = true;
        };
      }
    );

    test-guarded-home-alias-forwards-into-home-manager-root = denTest (
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
            fromClass = _: "home";
            intoClass = _: "homeManager";
            intoPath = _: [ ];
            fromAspect = _: lib.head aspect-chain;
            guard = { config, ... }: _: lib.mkIf config.programs.fish.enable;
            adaptArgs =
              { config, ... }:
              {
                osConfig = config;
              };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.nixos.networking.hostName = "storm";
        den.aspects.tux.homeManager.programs.fish.enable = true;

        den.aspects.tux = {
          includes = [ forwarded ];
          home =
            { osConfig, ... }:
            {
              home.keyboard.model = osConfig.networking.hostName;
            };
        };

        expr = {
          enable = igloo.home-manager.users.tux.programs.fish.enable;
          model = igloo.home-manager.users.tux.home.keyboard.model;
        };
        expected = {
          enable = true;
          model = "storm";
        };
      }
    );

    test-hm-platforms-example = denTest (
      {
        den,
        lib,
        igloo,
        apple,
        tuxHm,
        ...
      }:
      let
        forwarded =
          { class, aspect-chain }:
          den.provides.forward {
            each = [
              "Linux"
              "Darwin"
            ];
            fromClass = platform: "hm${platform}";
            intoClass = _: "homeManager";
            intoPath = _: [ ];
            fromAspect = _: lib.head aspect-chain;
            guard = { pkgs, ... }: platform: lib.mkIf pkgs.stdenv."is${platform}";
            adaptArgs =
              { config, ... }:
              {
                osConfig = config;
              };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.aarch64-darwin.apple.users.tux = { };

        den.aspects.tux = {
          includes = [
            forwarded
            den.aspects.foo
            den.aspects.bar
          ];
          hmLinux.home.keyboard.model = "freedom";
          hmDarwin.home.keyboard.model = "closed";
        };

        den.aspects.foo.hmLinux =
          { pkgs, ... }:
          {
            home.packages = [ pkgs.hello ];
          };

        den.aspects.bar.hmLinux =
          { pkgs, ... }:
          {
            home.packages = [ pkgs.direnv ];
          };

        expr = {
          linux = igloo.home-manager.users.tux.home.keyboard.model;
          darwin = apple.home-manager.users.tux.home.keyboard.model;
          hello = lib.any (p: "hello" == lib.getName p) tuxHm.home.packages;
          direnv = lib.any (p: "direnv" == lib.getName p) tuxHm.home.packages;
        };
        expected = {
          linux = "freedom";
          darwin = "closed";
          hello = true;
          direnv = true;
        };
      }
    );

  };
}
