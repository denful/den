{ denTest, ... }:
{
  flake.tests.conditional-config = {

    test-conditional-nixos-import = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;

        # A nixos module not always included
        # suppose this comes from inputs.<something>.nixosModules.default
        trueModule = {
          options.something = lib.mkOption { default = "was-true"; };
        };

        # fallback for test
        falseModule = {
          options.something = lib.mkOption { default = "was-false"; };
        };

        conditional = host: user: host.hasFoo && user.hasBar;

        conditionalAspect =
          { user, host, ... }:
          {
            # nixos module with conditional imports
            nixos =
              { pkgs, ... }:
              {
                imports = if conditional host user then [ trueModule ] else [ falseModule ];
              };
          };

      in
      {
        den.hosts.x86_64-linux.igloo = {
          hasFoo = true;
          users.tux.hasBar = true;
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [ conditionalAspect ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = igloo.something;
        expected = "was-true";
      }
    );

    test-conditional-hm-by-user-and-host = denTest (
      {
        den,
        lib,
        tuxHm,
        pinguHm,
        ...
      }:
      let
        inherit (den.lib.policy) include;

        git-for-linux-only =
          { user, host, ... }:
          if user.userName == "tux" then { homeManager.programs.git.enable = true; } else { };
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [ git-for-linux-only ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = [
          tuxHm.programs.git.enable
          pinguHm.programs.git.enable
        ];
        expected = [
          true
          false
        ];
      }
    );

    test-static-aspect-in-default = denTest (
      { den, igloo, ... }:
      let
        set-timezone = {
          nixos.time.timeZone = "UTC";
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ set-timezone ];

        expr = igloo.time.timeZone;
        expected = "UTC";
      }
    );

  };
}
