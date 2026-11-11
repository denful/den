# Where an exclude is written decides what it reaches. Reported in Matrix.
#
# - The entity's own aspect (`den.aspects.<host>`) is the entity: its excludes
#   reach as far as `den.hosts.<sys>.<host>.excludes`, the user's copy of
#   content included.
# - A host's provide to a user (`provides.<user>`, `provides.to-users`) can't
#   carry excludes in den v1: it is delivered after the user's includes are
#   resolved, so it is refused (exclude-reach-forms.nix).
# - An aspect the host merely includes keeps subtree reach.
#
# `feature` is in `den.default.includes`, so the host and the user each have a
# copy. It writes the user's account and a host-class list.
{ denTest, lib, ... }:
let
  cell =
    {
      excludes,
      expected,
      users ? {
        tux = { };
      },
      extra ? { },
    }:
    denTest (
      { config, den, ... }:
      {
        imports = [
          (excludes den)
          extra
        ];
        den.hosts.x86_64-linux.igloo.users = users;
        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };
        den.aspects.feature = {
          user.description = "from-feature";
          nixos.funny = [ "feature" ];
        };
        den.default.includes = [ den.aspects.feature ];
        expr =
          let
            c = config.flake.nixosConfigurations.igloo.config;
          in
          {
            accounts = lib.mapAttrs (_: u: u.description) (lib.filterAttrs (n: _: users ? ${n}) c.users.users);
            funny = c.funny;
          };
        inherit expected;
      }
    );
  ack.den.migrations.user-host-content.acknowledged = true;
  # tux's account and host content, and pingu's, when the user keeps feature
  kept = name: { ${name} = "from-feature"; };
  gone = name: { ${name} = ""; };
in
{
  flake.tests.c1.exclude-reach = {

    # Controls.
    test-no-exclude = cell {
      excludes = _: { };
      expected = {
        accounts = kept "tux";
        funny = [ "feature" ];
      };
    };
    test-user-excludes = cell {
      excludes = den: { den.aspects.tux.excludes = [ den.aspects.feature ]; };
      expected = {
        accounts = gone "tux";
        funny = [ "feature" ];
      };
    };
    test-instance-excludes = cell {
      excludes = den: { den.hosts.x86_64-linux.igloo.excludes = [ den.aspects.feature ]; };
      expected = {
        accounts = gone "tux";
        funny = [ ];
      };
    };

    # The host's own aspect reaches as far as the instance.
    test-host-aspect-excludes = cell {
      excludes = den: { den.aspects.igloo.excludes = [ den.aspects.feature ]; };
      expected = {
        accounts = gone "tux";
        funny = [ ];
      };
    };
    test-host-aspect-excludes-end-state = cell {
      excludes = den: { den.aspects.igloo.excludes = [ den.aspects.feature ]; };
      extra = ack;
      expected = {
        accounts = gone "tux";
        funny = [ ];
      };
    };

    # An aspect the host includes keeps subtree reach: the user's copy stays.
    test-included-aspect-excludes-subtree = cell {
      excludes = den: {
        den.aspects.ex.excludes = [ den.aspects.feature ];
        den.aspects.igloo.includes = [ den.aspects.ex ];
      };
      expected = {
        accounts = kept "tux";
        funny = [ "feature" ];
      };
    };

    # A host's excludes don't reach another host or its users.
    test-host-aspect-excludes-stay-on-host = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.feature.user.description = "from-feature";
        den.default.includes = [ den.aspects.feature ];
        den.aspects.igloo.excludes = [ den.aspects.feature ];
        expr = map (h: config.flake.nixosConfigurations.${h}.config.users.users.tux.description) [
          "igloo"
          "iceberg"
        ];
        expected = [
          ""
          "from-feature"
        ];
      }
    );

  }
  # An exclude names the aspect written there: a user's inline aspect that only
  # shares its name stays, at every reach.
  // lib.genAttrs' [ "instance" "schema" "host-aspect" ] (form: {
    name = "test-namesake-stays-${form}";
    value = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (
            {
              instance = {
                den.hosts.x86_64-linux.igloo.excludes = [ den.aspects.tools ];
              };
              schema = {
                den.schema.host.excludes = [ den.aspects.tools ];
              };
              host-aspect = {
                den.aspects.igloo.excludes = [ den.aspects.tools ];
              };
            }
            .${form}
          )
        ];
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        # The host accepts its users' host-class content.
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.aspects.tools.nixos.environment.etc.tools.text = "x";
        den.aspects.pingu.includes = [ den.aspects.tools ];
        den.aspects.tux.includes = [
          {
            name = "tools";
            nixos.environment.etc.inl.text = "x";
          }
        ];
        expr = {
          inl = igloo.environment.etc ? inl;
          tools = igloo.environment.etc ? tools;
        };
        expected = {
          inl = true;
          tools = false;
        };
      }
    );
  });
}
