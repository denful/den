# The examples in docs/src/content/docs/explanation/crossing-scopes.mdx that no
# other cell evaluates exactly. Each cell is the page's snippet.
{ denTest, lib, ... }:
let
  migration = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.schema.host.includes = [
      den.batteries.user-aspects
      den.batteries.mutual-provider
    ];
    den.aspects.tux = {
      nixos.boot.kernelModules = [ "own" ];
      provides.to-hosts.nixos.boot.kernelModules = [ "provided" ];
    };
  };
  mods = igloo: builtins.filter (m: m == "own" || m == "provided") igloo.boot.kernelModules;
in
{
  flake.tests.docs-crossing-scopes = {
    # "A migration that works both ways", with the defaults on.
    test-migration-defaults-on = denTest (
      { den, igloo, ... }:
      {
        imports = [ (migration den) ];
        den.internal.transitionDefaults = lib.mkForce true;
        expr = mods igloo;
        expected = [
          "own"
          "provided"
        ];
      }
    );
    # The same, acknowledged.
    test-migration-acknowledged = denTest (
      { den, igloo, ... }:
      {
        imports = [ (migration den) ];
        den.internal.transitionDefaults = lib.mkForce true;
        den.migrations.user-host-content.acknowledged = true;
        expr = mods igloo;
        expected = [
          "own"
          "provided"
        ];
      }
    );
    # Excluding mutual-provider during the transition: to-hosts content still
    # arrives through user-aspects' default; excluding both stops it.
    test-exclude-mutual-provider-alone-transition = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.prov.text = "x";
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? prov;
        expected = true;
      }
    );
    test-exclude-both-transition = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.prov.text = "x";
        den.aspects.igloo.excludes = [
          den.batteries.mutual-provider
          den.batteries.user-aspects
        ];
        expr = igloo.environment.etc ? prov;
        expected = false;
      }
    );
    test-exclude-mutual-provider-acknowledged = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.migrations.user-host-content.acknowledged = true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.prov.text = "x";
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? prov;
        expected = false;
      }
    );
  };
}
