# A provided module and its collision validator on the provenance route: a real
# collision fails the host, a non-colliding one lands. From an external review.
{ denTest, lib, ... }:
let
  ok =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v true);
    in
    r.success;
  drv = igloo: igloo.warnings;
  two = {
    den.hosts.x86_64-linux.igloo.users = {
      tux = { };
      pingu = { };
    };
    den.hosts.x86_64-linux.igloo.collisionPolicy = "error";
  };
  stack = den: {
    den.migrations.user-host-content.acknowledged = true;
    den.schema.host.includes = [ den.batteries.mutual-provider ];
  };
  plain = {
    den.aspects.tux.provides.to-hosts.nixos =
      { host, lib, ... }:
      {
        environment.etc.pv.text = host.name;
      };
  };
  suffixed = {
    den.aspects.tux.provides.to-hosts =
      { host, user, ... }:
      {
        nixos =
          { host, lib, ... }:
          {
            environment.etc."pv-${user.name}".text = host.name;
          };
      };
  };
  clash = {
    den.aspects.pingu.provides.to-hosts.nixos._module.args.host = "clash";
  };
  noclash = {
    den.aspects.pingu.provides.to-hosts.nixos._module.args.other = "fine";
  };
in
{
  flake.tests.provided-validator-routing = {
    test-v0-validator-works-on-host-own = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
        ];
        den.aspects.igloo.nixos =
          { host, lib, ... }:
          {
            environment.etc.own.text = host.name;
          };
        den.aspects.igloo.includes = [ { nixos._module.args.host = "clash"; } ];
        expr = ok (drv igloo);
        expected = false;
      }
    );
    test-v1-plain-collision-fails = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
          plain
          clash
        ];
        expr = ok (drv igloo);
        expected = false;
      }
    );
    test-v1c-plain-no-collision-evaluates = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
          plain
          noclash
        ];
        expr = {
          ok = ok (drv igloo);
          pv = igloo.environment.etc.pv.text or "<none>";
        };
        expected = {
          ok = true;
          pv = "igloo";
        };
      }
    );
    test-v2-suffixed-collision-fails = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
          suffixed
          clash
        ];
        expr = ok (drv igloo);
        expected = false;
      }
    );
    test-v2c-suffixed-no-collision-evaluates = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
          suffixed
          noclash
        ];
        expr = {
          ok = ok (drv igloo);
          pv = igloo.environment.etc.pv-tux.text or "<none>";
        };
        expected = {
          ok = true;
          pv = "igloo";
        };
      }
    );
    test-e1-plain-collision-error-text = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
          plain
          clash
        ];
        expr = igloo.warnings;
        expectedError = {
          type = "ThrownError";
          msg = "collides with module-system arg";
        };
      }
    );
    test-e2-suffixed-collision-error-text = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
          suffixed
          clash
        ];
        expr = igloo.warnings;
        expectedError = {
          type = "ThrownError";
          msg = "collides with module-system arg";
        };
      }
    );
    test-e0-host-own-collision-error-text = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
        ];
        den.aspects.igloo.nixos =
          { host, lib, ... }:
          {
            environment.etc.own.text = host.name;
          };
        den.aspects.igloo.includes = [ { nixos._module.args.host = "clash"; } ];
        expr = igloo.warnings;
        expectedError = {
          type = "ThrownError";
          msg = "collides with module-system arg";
        };
      }
    );
    test-n0-no-provider-control = denTest (
      { den, igloo, ... }:
      {
        imports = [
          two
          (stack den)
        ];
        expr = ok (drv igloo);
        expected = true;
      }
    );
  };
}
