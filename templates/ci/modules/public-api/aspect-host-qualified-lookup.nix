# `den.aspects."<user>@<host>"` — the host-qualified aspect target.
#
# A user-scoped entity resolves its aspect by trying the host-qualified name
# first and the bare user name second, at BOTH entity kinds: a user declared
# under a host, and a standalone home keyed `user@host`. Before this the
# qualified spelling was accepted by the aspect option and consulted by
# nothing, which is the same silent-drop shape as #663.
#
# COMPOSITION, not precedence: both aspects apply. That is forced rather than
# chosen — `modules/aspects/definition.nix` registers a stub aspect per entity,
# so `den.aspects ? <name>` is true for every declared entity whether or not
# anyone wrote it, and a stub is structurally identical to a written aspect. A
# "qualified wins" lookup would therefore match the stub and shadow the bare
# aspect for every entity. Composing is also the better semantic: a shared
# aspect and a host-specific one both apply. See nix/lib/entities/_types.nix.
{ denTest, ... }:
{
  flake.tests.aspect-host-qualified-lookup = {

    # --- host users -------------------------------------------------------

    test-user-takes-host-qualified-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects."tux@igloo".nixos.environment.etc."qualified".text = "yes";

        expr = igloo.environment.etc ? "qualified";
        expected = true;
      }
    );

    # CONTROL: the bare name still resolves when no qualified aspect exists.
    # This is the pre-existing behaviour, and without it the cell above could
    # pass for a change that broke bare-name lookup entirely.
    test-user-falls-back-to-bare-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.environment.etc."bare".text = "yes";

        expr = igloo.environment.etc ? "bare";
        expected = true;
      }
    );

    # Both defined: BOTH apply. Asserting the presence of the bare marker is
    # what discriminates composition from precedence — a cell reading only the
    # qualified marker passes under either semantics.
    test-user-composes-qualified-with-bare = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.environment.etc."bare".text = "yes";
        den.aspects."tux@igloo".nixos.environment.etc."qualified".text = "yes";

        expr = {
          qualified = igloo.environment.etc ? "qualified";
          bare = igloo.environment.etc ? "bare";
        };
        expected = {
          qualified = true;
          bare = true;
        };
      }
    );

    # The qualified name is per host, so the same user on two hosts can take
    # two different aspects. A single-host fixture cannot show this: it passes
    # for an implementation that ignores the host part entirely.
    test-user-qualified-is-per-host = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects."tux@igloo".nixos.environment.etc."on-igloo".text = "yes";
        den.aspects."tux@iceberg".nixos.environment.etc."on-iceberg".text = "yes";

        expr = {
          iglooHasIgloo = config.flake.nixosConfigurations.igloo.config.environment.etc ? "on-igloo";
          iglooHasIceberg = config.flake.nixosConfigurations.igloo.config.environment.etc ? "on-iceberg";
          icebergHasIceberg = config.flake.nixosConfigurations.iceberg.config.environment.etc ? "on-iceberg";
          icebergHasIgloo = config.flake.nixosConfigurations.iceberg.config.environment.etc ? "on-igloo";
        };
        expected = {
          iglooHasIgloo = true;
          iglooHasIceberg = false;
          icebergHasIceberg = true;
          icebergHasIgloo = false;
        };
      }
    );

    # --- standalone homes -------------------------------------------------

    # For a home keyed `tux@igloo` the registry key IS the qualified spelling,
    # so the same aspect name serves a home and a host user.
    test-home-takes-host-qualified-aspect = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects."tux@igloo".homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
          stateVersion = "25.05";
          sessionVariables.QUALIFIED = "yes";
        };

        expr =
          config.flake.homeConfigurations."tux@igloo".config.home.sessionVariables.QUALIFIED or "<missing>";
        expected = "yes";
      }
    );

    test-home-composes-qualified-with-bare = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.tux.homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
          stateVersion = "25.05";
          sessionVariables.BARE = "yes";
        };
        den.aspects."tux@igloo".homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
          stateVersion = "25.05";
          sessionVariables.QUALIFIED = "yes";
        };

        expr =
          let
            vars = config.flake.homeConfigurations."tux@igloo".config.home.sessionVariables;
          in
          {
            qualified = vars.QUALIFIED or "<missing>";
            bare = vars.BARE or "<missing>";
          };
        expected = {
          qualified = "yes";
          bare = "yes";
        };
      }
    );

    # CONTROL, and the load-bearing one: a home keyed `tux@igloo` must still
    # take `den.aspects.tux`. Reading the registry key ALONE would miss it and
    # resolve an EMPTY aspect — which throws nothing, and surfaces frames away
    # as home-manager's own `home.username != ""` assertion.
    test-home-falls-back-to-bare-aspect = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.tux.homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
          stateVersion = "25.05";
          sessionVariables.BARE = "yes";
        };

        expr = config.flake.homeConfigurations."tux@igloo".config.home.sessionVariables.BARE or "<missing>";
        expected = "yes";
      }
    );

    # A home keyed with no host has no qualified spelling to try, so both
    # candidates collapse to the bare name and the lookup still resolves.
    test-unqualified-home-resolves-bare = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.aspects.tux.homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
          stateVersion = "25.05";
          sessionVariables.BARE = "yes";
        };

        expr = config.flake.homeConfigurations.tux.config.home.sessionVariables.BARE or "<missing>";
        expected = "yes";
      }
    );

  };
}
