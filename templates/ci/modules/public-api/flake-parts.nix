{ denTest, inputs, ... }:
{

  flake.tests.flake-parts.inputs' = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.default.homeManager.home.stateVersion = "25.11";

      den.default.includes = [ den.provides.inputs' ];
      den.aspects.igloo.nixos =
        { inputs', ... }:
        {
          environment.systemPackages = [ inputs'.nixpkgs.legacyPackages.hello ];
        };

      expr = builtins.elem "hello" (map lib.getName igloo.environment.systemPackages);
      expected = true;
    }
  );

  flake.tests.flake-parts.self' = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.default.homeManager.home.stateVersion = "25.11";

      den.default.includes = [ den.provides.self' ];
      den.aspects.igloo.nixos =
        { self', ... }:
        {
          environment.systemPackages = [ self'.packages.hello ];
        };

      expr = builtins.elem "hello" (map lib.getName igloo.environment.systemPackages);
      expected = true;
    }
  );

}
