# Reported in GitHub #755: the collision validator den adds beside a
# parametric class module is bookkeeping, not content, so the transition
# warning doesn't list it. Its module is listed or not on its own account.
{ denTest, lib, ... }:
let
  base = {
    den.internal.transitionDefaults = lib.mkForce true;
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.theme.description = "a theme the user emits";
    den.aspects.tux.theme = {
      scheme = "rose-pine-moon";
    };
  };
  themed =
    { lib, theme, ... }:
    {
      environment.etc.theme.text = (lib.head theme).scheme;
    };
  lost =
    config:
    map (e: e.aspect) (
      config.flake.nixosConfigurations.igloo._module.args.denTransitionDefaultLost or [ ]
    );
in
{
  flake.tests.deadbugs.issue-755-validator-not-lost = {
    # Migrated to provides.to-hosts with mutual-provider explicit: nothing is
    # listed, and the module is delivered.
    test-migrated-lists-nothing = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        imports = [ base ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.stylix.provides.to-hosts.nixos = themed;
        den.aspects.tux.includes = [ den.aspects.stylix ];
        expr = {
          lost = lost config;
          text = igloo.environment.etc.theme.text or "<missing>";
        };
        expected = {
          lost = [ ];
          text = "rose-pine-moon";
        };
      }
    );
    # Not migrated: the aspect is listed once, without its validator.
    test-unmigrated-lists-the-aspect-only = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        imports = [ base ];
        den.aspects.stylix.nixos = themed;
        den.aspects.tux.includes = [ den.aspects.stylix ];
        expr = {
          lost = lost config;
          text = igloo.environment.etc.theme.text or "<missing>";
        };
        expected = {
          lost = [ "stylix" ];
          text = "rose-pine-moon";
        };
      }
    );
  };
}
