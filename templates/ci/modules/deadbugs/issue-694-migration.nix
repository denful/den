# Issue #694's transition defaults, until den.lib.migrations.removalDate. The
# suite runs with them off (test-support/end-state.nix); these cells turn them
# back on, as every config outside the suite has them.
#
# By default user-aspects and mutual-provider are on every host, so nothing
# changes from before #694, and a host warns once for the host-class content
# that reaches it only through them. The warning is `lib.warn`, which a cell
# cannot read: each cell that should warn uses its own user name, and the
# run's output carries exactly one `den: igloo receives nixos content only
# through den's transition default` naming `warn-<case>` per such cell, and
# none naming `quiet-<case>`.
{ denTest, lib, ... }:
let
  transition = {
    den.internal.transitionDefaults = lib.mkForce true;
  };
  # A placement-aware aspect: host-class content for a host placement, a home
  # part for a user placement.
  steam = {
    nixos.environment.etc.steam-host.text = "host";
    homeManager.home.sessionVariables.STEAM = "user";
  };
  homeUser = name: {
    den.hosts.x86_64-linux.igloo.users.${name}.classes = [ "homeManager" ];
    den.aspects.${name}.homeManager.home.stateVersion = "25.11";
  };
  hmOf = config: name: config.flake.nixosConfigurations.igloo.config.home-manager.users.${name};
in
{
  flake.tests.deadbugs.issue-694-migration = {

    # Guard: the removal date every message prints is a real date.
    test-removal-date-is-a-date = denTest (
      { den, ... }:
      {
        expr = builtins.match "[0-9]{4}-[0-9]{2}-[0-9]{2}" den.lib.migrations.removalDate != null;
        expected = true;
      }
    );

    # By default a user's own nixos still reaches the host, with a warning
    # (warn-default), as does what it provides to its hosts.
    test-default-changes-nothing = denTest (
      { den, igloo, ... }:
      {
        imports = [ transition ];
        den.hosts.x86_64-linux.igloo.users.warn-default = { };
        den.aspects.warn-default = {
          nixos.environment.etc.own.text = "user";
          provides.to-hosts.nixos.environment.etc.provided.text = "user";
        };
        expr = {
          own = igloo.environment.etc.own.text or "<missing>";
          provided = igloo.environment.etc.provided.text or "<missing>";
        };
        expected = {
          own = "user";
          provided = "user";
        };
      }
    );

    # The acknowledgement turns both defaults off: neither the user's own
    # nixos nor what it provides reaches the host (quiet-ack).
    test-acknowledgement-turns-both-off = denTest (
      { den, igloo, ... }:
      {
        imports = [ transition ];
        den.migrations.user-host-content.acknowledged = true;
        den.hosts.x86_64-linux.igloo.users.quiet-ack = { };
        den.aspects.quiet-ack = {
          nixos.environment.etc.own.text = "user";
          provides.to-hosts.nixos.environment.etc.provided.text = "user";
        };
        expr = {
          own = igloo.environment.etc ? own;
          provided = igloo.environment.etc ? provided;
        };
        expected = {
          own = false;
          provided = false;
        };
      }
    );

    # Explicit batteries: the content arrives through them, so no warning
    # (quiet-explicit). Both host policies fire for each battery (default and
    # explicit are two policies), but each delivery is one, so content lands
    # once.
    test-explicit-include-no-warning = denTest (
      { den, igloo, ... }:
      {
        imports = [ transition ];
        den.schema.host.includes = [
          den.batteries.user-aspects
          den.batteries.mutual-provider
        ];
        den.hosts.x86_64-linux.igloo.users.quiet-explicit = { };
        den.aspects.quiet-explicit = {
          nixos.boot.kernelModules = [ "own" ];
          provides.to-hosts.nixos.boot.kernelModules = [ "provided" ];
        };
        expr = builtins.filter (m: m == "own" || m == "provided") igloo.boot.kernelModules;
        expected = [
          "own"
          "provided"
        ];
      }
    );

    # Excluding a battery stops its default: with user-aspects excluded the
    # user's own nixos stays with it, while mutual-provider's default still
    # delivers what it provides, with a warning for that (warn-excluded).
    test-excluding-a-battery-stops-its-default = denTest (
      { den, igloo, ... }:
      {
        imports = [ transition ];
        den.schema.host.excludes = [ den.batteries.user-aspects ];
        den.hosts.x86_64-linux.igloo.users.warn-excluded = { };
        den.aspects.warn-excluded = {
          nixos.environment.etc.own.text = "user";
          provides.to-hosts.nixos.environment.etc.provided.text = "user";
        };
        expr = {
          own = igloo.environment.etc ? own;
          provided = igloo.environment.etc.provided.text or "<missing>";
        };
        expected = {
          own = false;
          provided = "user";
        };
      }
    );

    # The steam-shaped dual aspect placed on a user: by default unchanged
    # (the host part reaches the host) with a warning (warn-steam).
    test-dual-aspect-by-default = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [
          transition
          (homeUser "warn-steam")
        ];
        den.aspects.steam = steam;
        den.aspects.warn-steam.includes = [ den.aspects.steam ];
        expr = {
          host = igloo.environment.etc.steam-host.text or "<missing>";
          home = (hmOf config "warn-steam").home.sessionVariables.STEAM or "<missing>";
        };
        expected = {
          host = "host";
          home = "user";
        };
      }
    );

    # The same, acknowledged: the host part stays with the user, the home
    # part applies (quiet-steam).
    test-dual-aspect-acknowledged = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [
          transition
          (homeUser "quiet-steam")
        ];
        den.migrations.user-host-content.acknowledged = true;
        den.aspects.steam = steam;
        den.aspects.quiet-steam.includes = [ den.aspects.steam ];
        expr = {
          host = igloo.environment.etc ? steam-host;
          home = (hmOf config "quiet-steam").home.sessionVariables.STEAM or "<missing>";
        };
        expected = {
          host = false;
          home = "user";
        };
      }
    );

    # Host-placed: no warning (quiet-host).
    test-host-placed-no-warning = denTest (
      { den, igloo, ... }:
      {
        imports = [
          transition
          (homeUser "quiet-host")
        ];
        den.aspects.steam = steam;
        den.aspects.igloo.includes = [ den.aspects.steam ];
        expr = igloo.environment.etc.steam-host.text;
        expected = "host";
      }
    );
  };
}
