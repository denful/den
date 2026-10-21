{ denTest, ... }:
{
  flake.tests.deadbugs.standalone-qualified-home-inputs = {

    # FAILS: `user@host` standalone home, host not declared.
    test-qualified-home-inputs = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.batteries.define-user ];
        den.aspects."tux@igloo".includes = [ den.batteries.inputs' ];
        den.aspects.tux.homeManager =
          { inputs', ... }:
          {
            home.packages = [ inputs'.nixpkgs.legacyPackages.hello ];
          };

        expr = builtins.elem "hello" (
          map lib.getName config.flake.homeConfigurations."tux@igloo".config.home.packages
        );
        expected = true;
      }
    );

    # Same shape for `self'`, which the battery mirrors.
    test-qualified-home-self = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.batteries.define-user ];
        den.aspects."tux@igloo".includes = [ den.batteries.self' ];
        den.aspects.tux.homeManager =
          { self', ... }:
          {
            home.sessionVariables.SELF_PRIME = builtins.typeOf self';
          };

        expr = config.flake.homeConfigurations."tux@igloo".config.home.sessionVariables.SELF_PRIME;
        expected = "set";
      }
    );

    # `user@host` home whose host is declared: the user context is real here.
    test-qualified-home-declared-host-inputs = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux."tux@igloo" = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.batteries.define-user ];
        den.aspects."tux@igloo".includes = [ den.batteries.inputs' ];
        den.aspects.tux.homeManager =
          { inputs', ... }:
          {
            home.packages = [ inputs'.nixpkgs.legacyPackages.hello ];
          };

        expr = builtins.elem "hello" (
          map lib.getName config.flake.homeConfigurations."tux@igloo".config.home.packages
        );
        expected = true;
      }
    );

    # CONTROL (passes): plain `user` standalone home.
    test-plain-home-inputs = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.batteries.define-user ];
        den.aspects.tux.includes = [ den.batteries.inputs' ];
        den.aspects.tux.homeManager =
          { inputs', ... }:
          {
            home.packages = [ inputs'.nixpkgs.legacyPackages.hello ];
          };

        expr = builtins.elem "hello" (
          map lib.getName config.flake.homeConfigurations.tux.config.home.packages
        );
        expected = true;
      }
    );

  };
}
