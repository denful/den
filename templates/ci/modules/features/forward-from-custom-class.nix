{ denTest, ... }:
{
  flake.tests.forward-custom-class = {

    test-forward-custom-class-to-nixos = denTest (
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
            fromClass = _: "custom";
            intoClass = _: "nixos";
            intoPath = _: [ ];
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [ forwarded ];
          custom.networking.hostName = "from-custom-class";
        };

        expr = igloo.networking.hostName;
        expected = "from-custom-class";
      }
    );

    test-forward-into-subpath = denTest (
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
            intoClass = _: "nixos";
            intoPath = _: [ "fwd-box" ];
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [ forwarded ];
          nixos.imports = [
            { options.fwd-box = lib.mkOption { type = lib.types.submoduleWith { modules = [ fwdModule ]; }; }; }
          ];
          nixos.fwd-box.items = [ "from-nixos-owned" ];
          src.items = [ "from-src-class" ];
        };

        expr = lib.sort (a: b: a < b) igloo.fwd-box.items;
        expected = [
          "from-nixos-owned"
          "from-src-class"
        ];
      }
    );

    test-custom-git-class-fowards-to-hm-then-nixos = denTest (
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
            fromClass = _: "git";
            intoClass = _: "homeManager";
            intoPath = _: [
              "programs"
              "git"
            ];
            fromAspect = _: lib.head aspect-chain;
            adaptArgs =
              { config, ... }:
              {
                osConfig = config;
              };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.homeManager.home.stateVersion = "25.11";

        den.aspects.tux = {
          includes = [ forwarded ];
          git.userEmail = "root@linux.com";
        };

        expr = igloo.home-manager.users.tux.programs.git.userEmail;
        expected = "root@linux.com";
      }
    );

    test-custom-nix-class-fowards-to-both-hm-and-nixos = denTest (
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
            each = [
              "nixos"
              "homeManager"
            ];
            fromClass = _: "nix";
            intoClass = lib.id;
            intoPath = _: [ "nix" ];
            fromAspect = _: lib.head aspect-chain;
            adaptArgs =
              { config, ... }:
              {
                osConfig = config;
              };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.homeManager.home.stateVersion = "25.11";

        den.aspects.tux = {
          includes = [ forwarded ];
          nix.settings.allowed-users = [ "tux" ];
        };

        expr = {
          os = igloo.nix.settings.allowed-users;
          hm = igloo.home-manager.users.tux.nix.settings.allowed-users;
        };
        expected = {
          os = [ "tux" ];
          hm = [ "tux" ];
        };
      }
    );

    test-pair-of-hosts = denTest (
      {
        den,
        lib,
        igloo,
        iceberg,
        ...
      }:
      let
        forwarded =
          { host, user }:
          { class, aspect-chain }:
          den.provides.forward {
            each = lib.optional (lib.elem host.name [
              "igloo"
              "iceberg"
            ]) user;
            fromClass = _: "iced";
            intoClass = _: host.class;
            intoPath = _: [ ];
            fromAspect = _: lib.head aspect-chain;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };

        den.aspects.igloo.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ forwarded ];

        den.aspects.tux = {
          iced.networking.hostName = "iced";
        };

        expr = [
          igloo.networking.hostName
          iceberg.networking.hostName
        ];
        expected = [
          "iced"
          "iced"
        ];
      }
    );

  };
}
