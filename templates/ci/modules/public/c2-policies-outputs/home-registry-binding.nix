# Standalone homes bind `den.users.<userName>` like a host user does (#781,
# decision 6): the registry user, plus the relation's override only on a host
# declared in the home's own system, with `classes` the home's.
{ denTest, lib, ... }:
let
  shellOption = {
    den.schema.user.imports = [
      {
        options.shell = lib.mkOption {
          type = lib.types.str;
          default = "bash";
        };
      }
    ];
  };
  homeOf =
    den: system: name:
    den.homes.${system}.${name};
  hmOf = config: out: config.flake.homeConfigurations.${out}.config;

  # Present only when `homeManager` is in the user's classes, read through the
  # built home-manager config.
  classMarker = {
    homeManager =
      { user, ... }:
      {
        home.sessionVariables = lib.optionalAttrs (builtins.elem "homeManager" user.classes) {
          DEN_CLASS_MARKER = "homeManager";
        };
      };
  };
in
{
  flake.tests.home-registry-binding = {

    test-home-registers-its-user = denTest (
      { den, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.homes.x86_64-linux.cam.userName = "cameron";
        expr = {
          tux = den.users ? tux;
          cameron = den.users ? cameron;
        };
        expected = {
          tux = true;
          cameron = true;
        };
      }
    );

    test-plain-home-sees-registry-fields = denTest (
      { den, ... }:
      {
        den.users.tux.email = "tux@example.com";
        den.homes.x86_64-linux.tux = { };
        expr = (homeOf den "x86_64-linux" "tux").user.email;
        expected = "tux@example.com";
      }
    );

    # A plain home gets the base fields, never another host's override.
    test-plain-home-ignores-other-hosts-override = denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.users.tux.shell = "zsh";
        den.hosts.x86_64-linux.igloo.users.tux.shell = "fish";
        den.homes.x86_64-linux.tux = { };
        expr = {
          home = (homeOf den "x86_64-linux" "tux").user.shell;
          host = den.hosts.x86_64-linux.igloo.users.tux.shell;
        };
        expected = {
          home = "zsh";
          host = "fish";
        };
      }
    );

    # On a host declared in the home's system, the home sees that relation.
    test-attached-home-sees-the-relation = denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.users.tux.shell = "zsh";
        den.hosts.x86_64-linux.igloo.users.tux.shell = "fish";
        den.homes.x86_64-linux."tux@igloo" = { };
        expr = (homeOf den "x86_64-linux" "tux@igloo").user.shell;
        expected = "fish";
      }
    );

    # The same `@igloo` on a system where igloo isn't declared is context
    # only: no override.
    test-undeclared-host-adds-no-override = denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.users.tux.shell = "zsh";
        den.hosts.x86_64-linux.igloo.users.tux.shell = "fish";
        den.homes.aarch64-linux."tux@igloo" = { };
        expr = (homeOf den "aarch64-linux" "tux@igloo").user.shell;
        expected = "zsh";
      }
    );

    # The attached home's `user.classes` is the home's class, so content that
    # depends on `homeManager` being among them now appears; the host user's
    # own classes and the host's output stay as they were.
    test-attached-home-takes-the-home-class = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "user" ];
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.tux = {
          includes = [ classMarker ];
          homeManager.programs.fish.enable = true;
        };
        expr = {
          marker = (hmOf config "tux@igloo").home.sessionVariables.DEN_CLASS_MARKER or "absent";
          fish = (hmOf config "tux@igloo").programs.fish.enable;
          homeClasses = (homeOf den "x86_64-linux" "tux@igloo").user.classes;
          hostClasses = den.hosts.x86_64-linux.igloo.users.tux.classes;
          hostAccount = igloo.users.users.tux.isNormalUser;
        };
        expected = {
          marker = "homeManager";
          fish = true;
          homeClasses = [ "homeManager" ];
          hostClasses = [ "user" ];
          hostAccount = true;
        };
      }
    );

    # No registry entry and no declared host: the home builds as before.
    test-unregistered-plain-home-keeps-its-output = denTest (
      { den, config, ... }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.homes.x86_64-linux.tux = { };
        den.aspects.tux.homeManager.programs.fish.enable = true;
        expr = {
          inherit ((hmOf config "tux").home) username;
          fish = (hmOf config "tux").programs.fish.enable;
        };
        expected = {
          username = "tux";
          fish = true;
        };
      }
    );

    test-undeclared-host-creates-no-account = denTest (
      { den, igloo, ... }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.hosts.x86_64-linux.igloo.users.pingu = { };
        den.homes.x86_64-linux."tux@astra" = { };
        expr = {
          igloo = igloo.users.users ? tux;
          onIgloo = den.hosts.x86_64-linux.igloo.users ? tux;
        };
        expected = {
          igloo = false;
          onIgloo = false;
        };
      }
    );

    # A registry user with only a home runs its home aspects and isn't
    # reported hostless.
    test-home-only-user-runs-and-is-not-warned = denTest (
      { den, config, ... }:
      {
        den.internal.warningsAsErrors = true;
        den.default.includes = [ den.provides.define-user ];
        den.users.homebody.email = "home@example.com";
        den.homes.x86_64-linux.homebody = { };
        den.aspects.homebody.homeManager.programs.fish.enable = true;
        expr = {
          fish = (hmOf config "homebody").programs.fish.enable;
          hostless = den.internal.hostlessUsers;
        };
        expected = {
          fish = true;
          hostless = [ ];
        };
      }
    );

  };
}
