# Every form of a host's own exclude reaches as far as the host's instance
# exclude (exclude-reach.nix). A host's provide to a user that sets `excludes`
# is refused, however it is written. A host aspect's `handleWith` keeps its
# reach.
# Reported in Matrix.
{ denTest, lib, ... }:
let
  base = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.hosts.x86_64-linux.igloo.includes = [ den.aspects.opts ];
    den.aspects.opts.nixos.options.funny = lib.mkOption {
      default = [ ];
      type = lib.types.listOf lib.types.str;
    };
    den.aspects.feature = {
      user.description = "from-feature";
      nixos.funny = [ "feature" ];
    };
    den.default.includes = [ den.aspects.feature ];
  };
  out = config: {
    tux = config.flake.nixosConfigurations.igloo.config.users.users.tux.description;
    funny = config.flake.nixosConfigurations.igloo.config.funny;
  };
  gone = {
    tux = "";
    funny = [ ];
  };
in
{
  flake.tests.c1.exclude-reach-forms = {

    test-parametric-host-aspect = denTest (
      { config, den, ... }:
      {
        imports = [ (base den) ];
        den.aspects.igloo =
          { host, ... }:
          {
            excludes = [ den.aspects.feature ];
          };
        expr = out config;
        expected = gone;
      }
    );
    test-parametric-definition-beside-static = denTest (
      { config, den, ... }:
      {
        imports = [
          (base den)
          {
            den.aspects.igloo =
              { host, ... }:
              {
                excludes = [ den.aspects.feature ];
              };
          }
        ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        expr = out config;
        expected = gone;
      }
    );
    test-policy-exclude-in-host-aspect = denTest (
      { config, den, ... }:
      {
        imports = [ (base den) ];
        den.policies.drop-feature = { host, ... }: [ (den.lib.policy.exclude den.aspects.feature) ];
        den.aspects.igloo.includes = [ den.policies.drop-feature ];
        expr = out config;
        expected = gone;
      }
    );
    test-policy-exclude-in-instance = denTest (
      { config, den, ... }:
      {
        imports = [ (base den) ];
        den.policies.drop-feature = { host, ... }: [ (den.lib.policy.exclude den.aspects.feature) ];
        den.hosts.x86_64-linux.igloo.includes = [ den.policies.drop-feature ];
        expr = out config;
        expected = gone;
      }
    );

    # A host's provide to a user that sets `excludes` is refused, in every form.
    test-provides-user-excludes-refused = denTest (
      { config, den, ... }:
      {
        imports = [ (base den) ];
        den.aspects.igloo.provides.tux.excludes = [ den.aspects.feature ];
        expr = out config;
        expectedError = {
          type = "ThrownError";
          msg = "can't apply";
        };
      }
    );
    test-provides-to-users-excludes-refused = denTest (
      { config, den, ... }:
      {
        imports = [ (base den) ];
        den.aspects.igloo.provides.to-users.excludes = [ den.aspects.feature ];
        expr = out config;
        expectedError = {
          type = "ThrownError";
          msg = "can't apply";
        };
      }
    );
    test-parametric-provide-excludes-refused = denTest (
      { config, den, ... }:
      {
        imports = [
          (base den)
          {
            den.aspects.igloo.provides.tux =
              { user, ... }:
              {
                excludes = [ den.aspects.feature ];
              };
          }
        ];
        den.aspects.igloo.provides.tux.homeManager = { };
        expr = out config;
        expectedError = {
          type = "ThrownError";
          msg = "can't apply";
        };
      }
    );
    # A provide without excludes is delivered as before.
    test-provides-user-without-excludes = denTest (
      { config, den, ... }:
      {
        imports = [ (base den) ];
        den.aspects.igloo.provides.tux.user.extraGroups = [ "provided" ];
        expr = builtins.elem "provided" config.flake.nixosConfigurations.igloo.config.users.users.tux.extraGroups;
        expected = true;
      }
    );

    # The host's own `handleWith` keeps the aspect's reach: the user's copy
    # stays, and so does another host's.
    test-host-aspect-handlewith-keeps-reach = denTest (
      { config, den, ... }:
      {
        imports = [ (base den) ];
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.iceberg.includes = [ den.aspects.opts ];
        den.aspects.igloo.meta.handleWith = den.lib.aspects.fx.constraints.filterBy (
          a: (a.name or "") != "feature"
        );
        expr = map (h: config.flake.nixosConfigurations.${h}.config.users.users.tux.description) [
          "igloo"
          "iceberg"
        ];
        expected = [
          "from-feature"
          "from-feature"
        ];
      }
    );

  };
}
