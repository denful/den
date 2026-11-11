# A class module requiring `user` at host scope emits once per user (#629).
# Only that module fans: the aspect's other class content and its includes stay
# at the host, once, whatever the number of users, so a host with no users
# keeps them. Reported in Matrix.
#
# `funny` is a plain list option (no dedup), so a duplicated or dropped
# definition shows in the list.
{ denTest, lib, ... }:
let
  funnyOption = lib.mkOption {
    default = [ ];
    type = lib.types.listOf lib.types.str;
  };

  cell =
    {
      users,
      feature,
      expected,
      extraModules ? [ ],
    }:
    denTest (
      { den, config, ... }:
      {
        imports = extraModules;
        den.hosts.x86_64-linux.glacier.users = users;
        den.aspects.glacier.nixos.options.funny = funnyOption;
        den.aspects.other.nixos.funny = [ "include" ];
        den.aspects.feature = feature den;
        den.aspects.glacier.includes = [ den.aspects.feature ];
        expr = lib.sort lib.lessThan config.flake.nixosConfigurations.glacier.config.funny;
        inherit expected;
      }
    );

  none = { };
  one.tux = { };
  two = {
    tux = { };
    pingu = { };
  };

  # The report: static content beside a module that requires `user`.
  withHmUser = den: {
    nixos.funny = [ "static" ];
    includes = [ den.aspects.other ];
    homeManager = { user, ... }: { };
  };
  withUserClass = den: {
    nixos.funny = [ "static" ];
    includes = [ den.aspects.other ];
    user = { user, ... }: { };
  };
  # The fanned module itself is host-class content (#629).
  fannedNixos = den: {
    nixos =
      { user, ... }:
      {
        funny = [ "fan ${user.name}" ];
      };
    homeManager.programs.git.enable = true;
    includes = [ den.aspects.other ];
  };
  # An optional `user` is not required: applied once, without a user.
  optionalUser = _: {
    nixos =
      {
        user ? null,
        ...
      }:
      {
        funny = [ (if user == null then "no user" else "fan ${user.name}") ];
      };
  };
in
{
  flake.tests.c1.userless-host-class-fan = {

    test-userless-keeps-static-and-includes = cell {
      users = none;
      feature = withHmUser;
      expected = [
        "include"
        "static"
      ];
    };
    test-userless-user-class = cell {
      users = none;
      feature = withUserClass;
      expected = [
        "include"
        "static"
      ];
    };
    test-userless-fanned-module-emits-nothing = cell {
      users = none;
      feature = fannedNixos;
      expected = [ "include" ];
    };

    test-one-user-static-once = cell {
      users = one;
      feature = withHmUser;
      expected = [
        "include"
        "static"
      ];
    };
    test-two-users-static-once = cell {
      users = two;
      feature = withHmUser;
      expected = [
        "include"
        "static"
      ];
    };
    test-two-users-fanned-module-per-user = cell {
      users = two;
      feature = fannedNixos;
      expected = [
        "fan pingu"
        "fan tux"
        "include"
      ];
    };
    test-two-users-optional-user-once = cell {
      users = two;
      feature = optionalUser;
      expected = [ "no user" ];
    };

    # A source included at both the host and user kinds (den.default's shape):
    # each user's copy lands once, not once from each scope.
    test-shared-source-once-per-user = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.glacier.users = two;
        den.aspects.glacier.nixos.options.funny = funnyOption;
        den.aspects.shared.nixos =
          { user, ... }:
          {
            funny = [ "shared ${user.name}" ];
          };
        den.schema.host.includes = [
          den.batteries.user-aspects
          den.aspects.shared
        ];
        den.schema.user.includes = [ den.aspects.shared ];
        expr = lib.sort lib.lessThan config.flake.nixosConfigurations.glacier.config.funny;
        expected = [
          "shared pingu"
          "shared tux"
        ];
      }
    );
    test-den-default-once-per-user = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.glacier.users = two;
        den.aspects.glacier.nixos.options.funny = funnyOption;
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.default.nixos =
          { user, ... }:
          {
            funny = [ "default ${user.name}" ];
          };
        expr = lib.sort lib.lessThan config.flake.nixosConfigurations.glacier.config.funny;
        expected = [
          "default pingu"
          "default tux"
        ];
      }
    );

    # One key defined twice, statically and requiring `user`: the static
    # definition lands once and the other once per user, with or without a
    # sibling key that also requires `user`.
    test-two-definitions-of-a-key = cell {
      users = two;
      feature = _: { };
      extraModules = [
        { den.aspects.feature.nixos.funny = [ "static" ]; }
        {
          den.aspects.feature.nixos =
            { user, ... }:
            {
              funny = [ "fan ${user.name}" ];
            };
        }
      ];
      expected = [
        "fan pingu"
        "fan tux"
        "static"
      ];
    };
    test-two-definitions-of-a-key-beside-hm-user = cell {
      users = two;
      feature = _: { homeManager = { user, ... }: { }; };
      extraModules = [
        { den.aspects.feature.nixos.funny = [ "static" ]; }
        {
          den.aspects.feature.nixos =
            { user, ... }:
            {
              funny = [ "fan ${user.name}" ];
            };
        }
      ];
      expected = [
        "fan pingu"
        "fan tux"
        "static"
      ];
    };

  };
}
