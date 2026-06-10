# Host-conditional config in a standalone home resolves when the home is named
# `user@host`. A declared host is used directly; an undeclared host yields a
# synthetic `{ name = host; }` identity (home.nix) so host-name-keyed policies
# and `provides.<host>` resolve without instantiating a real host (no platform
# builder like nix-darwin). A plain (no `@host`) home has no host context, so
# host-keyed effects stay inert there.
#
# Mostly uses a linux/nixos host to exercise the (class-agnostic) host-context
# mechanism; one darwin test proves no nix-darwin instantiation is needed.
{ denTest, ... }:
{
  flake.tests.deadbugs.standalone-home-host-context = {

    # Unbound standalone home: `host` absent from ctx → host policy never fires.
    test-unbound-home-host-policy-does-not-fire = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux.ben = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.includes = [
          (den.lib.policy.when ({ host, ... }: host.name == "homehost") (
            _: den.lib.policy.include { homeManager.programs.zsh.profileExtra = "brew"; }
          ))
        ];

        expr = config.flake.homeConfigurations.ben.config.programs.zsh.profileExtra;
        expected = "";
      }
    );

    # `user@host` naming WITHOUT declaring the host: home.nix synthesizes a
    # minimal `{ name = "homehost"; }` host identity from the name, so the
    # host-keyed policy fires — no `den.hosts` entry (and no host instantiation)
    # required. This is what lets a standalone home select host config without
    # importing the host's platform builder (nix-darwin, etc.).
    test-at-host-naming-synthesizes-host-and-fires = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux."ben@homehost" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.includes = [
          (den.lib.policy.when ({ host, ... }: host.name == "homehost") (
            _: den.lib.policy.include { homeManager.programs.zsh.profileExtra = "brew"; }
          ))
        ];

        expr = config.flake.homeConfigurations."ben@homehost".config.programs.zsh.profileExtra;
        expected = "brew";
      }
    );

    # Bound home (`user@host`, host declared): `host` enters ctx → policy fires.
    test-bound-home-when-policy-fires = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.homehost.users.ben = { };
        den.homes.x86_64-linux."ben@homehost" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.includes = [
          (den.lib.policy.when ({ host, ... }: host.name == "homehost") (
            _: den.lib.policy.include { homeManager.programs.zsh.profileExtra = "brew"; }
          ))
        ];

        expr = config.flake.homeConfigurations."ben@homehost".config.programs.zsh.profileExtra;
        expected = "brew";
      }
    );

    # Bound home, raw-function include returning a list of effects
    # (`lib.optional cond (policy.include {...})`). The parametric path now
    # normalizes a list return into includes instead of throwing
    # "expected a set but found a list".
    test-bound-home-list-returning-include-fires = denTest (
      {
        config,
        den,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.homehost.users.ben = { };
        den.homes.x86_64-linux."ben@homehost" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.includes = [
          (
            { host, ... }:
            lib.optional (host.name == "homehost") (
              den.lib.policy.include { homeManager.programs.zsh.profileExtra = "brew"; }
            )
          )
        ];

        expr = config.flake.homeConfigurations."ben@homehost".config.programs.zsh.profileExtra;
        expected = "brew";
      }
    );

    # A list-returning include with multiple include effects applies all of them.
    test-bound-home-multi-include-list-applies-all = denTest (
      {
        config,
        den,
        ...
      }:
      {
        den.hosts.x86_64-linux.homehost.users.ben = { };
        den.homes.x86_64-linux."ben@homehost" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.includes = [
          (
            { host, ... }:
            [
              (den.lib.policy.include { homeManager.programs.zsh.profileExtra = "from-profile"; })
              (den.lib.policy.include { homeManager.programs.zsh.initExtra = "from-init"; })
            ]
          )
        ];

        expr = {
          profile = config.flake.homeConfigurations."ben@homehost".config.programs.zsh.profileExtra;
          init = config.flake.homeConfigurations."ben@homehost".config.programs.zsh.initExtra;
        };
        expected = {
          profile = "from-profile";
          init = "from-init";
        };
      }
    );

    # A list-returning include carrying a non-include effect (here `exclude`)
    # can't be expressed as a parametric include merge — clear `den:` error.
    test-bound-home-list-with-non-include-effect-throws = denTest (
      {
        config,
        den,
        ...
      }:
      {
        den.hosts.x86_64-linux.homehost.users.ben = { };
        den.homes.x86_64-linux."ben@homehost" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.includes = [
          ({ host, ... }: [ (den.lib.policy.exclude { homeManager.programs.zsh.enable = true; }) ])
        ];

        expectedError = {
          type = "ThrownError";
          msg = "returned a 'exclude' effect in a list";
        };
        expr = config.flake.homeConfigurations."ben@homehost".config.home.username;
      }
    );

    # Bound home, `provides.<hostname>` cross-delivery form also fires.
    test-bound-home-provides-form-fires = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.homehost.users.ben = { };
        den.homes.x86_64-linux."ben@homehost" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.provides.homehost = {
          homeManager.programs.zsh.profileExtra = "brew";
        };

        expr = config.flake.homeConfigurations."ben@homehost".config.programs.zsh.profileExtra;
        expected = "brew";
      }
    );

    # Faithful to the user's original report: a darwin standalone home using
    # `provides.<hostname>` with a hyphenated host name (quoted attr key,
    # matched by `host.name == key`) and a multiline profileExtra. No host is
    # declared and no nix-darwin input is imported — the `user@host` name
    # synthesizes the host identity, so the cross-policy fires.
    test-darwin-home-provides-synthetic-host-grammar = denTest (
      { config, den, ... }:
      {
        den.homes.aarch64-darwin."ben@Bens-MacBook-Pro" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/Users/ben";
        };
        den.aspects.ben.provides.Bens-MacBook-Pro = {
          homeManager.programs.zsh.profileExtra = ''
            eval "$(/opt/homebrew/bin/brew shellenv zsh)"
          '';
        };

        expr = config.flake.homeConfigurations."ben@Bens-MacBook-Pro".config.programs.zsh.profileExtra;
        expected = ''
          eval "$(/opt/homebrew/bin/brew shellenv zsh)"
        '';
      }
    );

    # The `hostname` battery (a `{ host }`-keyed OS aspect, documented for
    # `den.default.includes`) must not throw on a synthetic-host home: its
    # `${host.class}` emission is gated on `host ? class`, so it stays inert
    # for a classless synthetic host while the home still evaluates.
    test-hostname-battery-inert-on-synthetic-host = denTest (
      { config, den, ... }:
      {
        den.default.includes = [ den.batteries.hostname ];

        den.homes.x86_64-linux."ben@homehost" = { };
        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };

        expr = config.flake.homeConfigurations."ben@homehost".config.home.username;
        expected = "ben";
      }
    );

    # A list-returning include may nest lists; they are flattened so every
    # effect is reached rather than silently dropped.
    test-bound-home-nested-list-include-fires = denTest (
      {
        config,
        den,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.homehost.users.ben = { };
        den.homes.x86_64-linux."ben@homehost" = { };

        den.aspects.ben.homeManager.home = {
          username = "ben";
          homeDirectory = "/home/ben";
        };
        den.aspects.ben.includes = [
          (
            { host, ... }:
            [
              (lib.optional (host.name == "homehost") (
                den.lib.policy.include { homeManager.programs.zsh.profileExtra = "brew"; }
              ))
            ]
          )
        ];

        expr = config.flake.homeConfigurations."ben@homehost".config.programs.zsh.profileExtra;
        expected = "brew";
      }
    );

  };
}
