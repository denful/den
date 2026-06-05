{ denTest, ... }:
{
  flake.tests.parametric = {

    test-parametric-forwards-context = denTest (
      { den, igloo, ... }:
      let
        foo = den.lib.parametric {
          includes = [
            (
              { host, ... }:
              {
                nixos.users.users.tux.description = host.name;
              }
            )
          ];
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ foo ];

        expr = igloo.users.users.tux.description;
        expected = "igloo";
      }
    );

    test-parametric-owned-config = denTest (
      { den, igloo, ... }:
      let
        foo = den.lib.parametric {
          nixos.networking.hostName = "from-parametric-owned";
          includes = [ ];
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ foo ];

        expr = igloo.networking.hostName;
        expected = "from-parametric-owned";
      }
    );

    test-parametric-fixedTo = denTest (
      { den, igloo, ... }:
      let
        foo =
          { host, ... }:
          den.lib.parametric.fixedTo { planet = "Earth"; } {
            includes = [
              (
                { planet, ... }:
                {
                  nixos.users.users.tux.description = planet;
                }
              )
            ];
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ foo ];

        expr = igloo.users.users.tux.description;
        expected = "Earth";
      }
    );

    test-parametric-expands = denTest (
      { den, igloo, ... }:
      let
        foo = den.lib.parametric.expands { planet = "Earth"; } {
          includes = [
            (
              { host, planet, ... }:
              {
                nixos.users.users.tux.description = "${host.name}/${planet}";
              }
            )
          ];
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ foo ];

        expr = igloo.users.users.tux.description;
        expected = "igloo/Earth";
      }
    );

    # Parametric aspect including a static named aspect — owned configs
    # on the static aspect must not be dropped by applyDeep recursion.
    test-parametric-including-static-named-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.base.nixos =
          { ... }:
          {
            programs.git.enable = true;
          };

        den.aspects.dev =
          { user, ... }:
          {
            includes = [ den.aspects.base ];
          };

        den.aspects.tux.includes = [ den.aspects.dev ];

        expr = igloo.programs.git.enable;
        expected = true;
      }
    );

    # Named aspect with both owned class config and parametric includes,
    # referenced from inside a parametric function's bare result.
    test-parametric-including-mixed-owned-and-parametric = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tools = {
          nixos =
            { ... }:
            {
              programs.git.enable = true;
            };
          includes = [
            (
              { user, ... }:
              {
                nixos =
                  { ... }:
                  {
                    programs.zsh.enable = true;
                  };
              }
            )
          ];
        };

        den.aspects.role =
          { user, ... }:
          {
            includes = [ den.aspects.tools ];
          };

        den.aspects.tux.includes = [ den.aspects.role ];

        expr = {
          git = igloo.programs.git.enable;
          zsh = igloo.programs.zsh.enable;
        };
        expected = {
          git = true;
          zsh = true;
        };
      }
    );

    # Factory function aspect called inside a nested parametric chain.
    test-factory-in-nested-parametric-chain = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.greeter = greeting: {
          nixos =
            { ... }:
            {
              users.users.tux.description = greeting;
            };
        };

        den.aspects.role =
          { user, ... }:
          {
            includes = [ (den.aspects.greeter "hello") ];
          };

        den.aspects.tux.includes = [ den.aspects.role ];

        expr = igloo.users.users.tux.description;
        expected = "hello";
      }
    );

    test-never-matches-aspect-skipped = denTest (
      { den, igloo, ... }:
      let
        never-matches =
          { never-exists, ... }:
          {
            nixos.networking.hostName = "NEVER";
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = den.lib.parametric {
          includes = [
            den.provides.hostname
            never-matches
          ];
        };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

  };
}
