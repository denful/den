{ denTest, ... }:
{
  flake.tests.deadbugs-issue-369 = {

    test-self-arg-includes = denTest (
      {
        den,
        lib,
        inputs,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        den.default.includes = [ den.provides.self' ];
        den.aspects.tux.includes = [ den.aspects.hola ];

        den.aspects.hola.homeManager =
          { self', ... }@args:
          {
            home.sessionVariables.FOO = lib.getName self'.legacyPackages.hello;
          };

        expr = tuxHm.home.sessionVariables.FOO;
        expected = "hello";
      }
    );

    test-inputs-arg-includes = denTest (
      {
        den,
        lib,
        inputs,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        den.default.includes = [ den.provides.inputs' ];
        den.aspects.tux.includes = [ den.aspects.hola ];

        den.aspects.hola.homeManager =
          { inputs', ... }@args:
          {
            home.sessionVariables.FOO = lib.getName inputs'.nixpkgs.legacyPackages.hello;
          };

        expr = tuxHm.home.sessionVariables.FOO;
        expected = "hello";
      }
    );

    test-everything-includes = denTest (
      {
        den,
        lib,
        igloo,
        inputs,
        gloom,
        __findFile,
        tuxHm,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "gloom" false) ];
        _module.args.__findFile = den.lib.__findFile;

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        den.default.includes = [
          den.provides.inputs'
          den.provides.define-user
        ];
        den.aspects.tux.includes = [ gloom.everywhere ];
        gloom.everywhere.includes = [ <gloom/apps/helix> ];

        gloom.apps.provides.helix.homeManager =
          { inputs', ... }@args:
          {
            home.packages = [ inputs'.nixpkgs.legacyPackages.hello ];
          };

        expr = builtins.elem "hello" (map lib.getName tuxHm.home.packages);
        expected = true;
      }
    );

  };
}
