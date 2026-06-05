{ denTest, ... }:
{
  flake.tests.unfree = {

    test-packages-set-on-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ (den.provides.unfree [ "discord" ]) ];
        expr = igloo.nixpkgs.config.allowUnfreePredicate { pname = "discord"; };
        expected = true;
      }
    );

    test-packages-set-on-home-manager = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [ (den.provides.unfree [ "vscode" ]) ];

        expr = tuxHm.nixpkgs.config.allowUnfreePredicate { pname = "vscode"; };
        expected = true;
      }
    );

    test-user-class-works = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den.provides.unfree [ "vscode" ]) ];

        expr = !(igloo.users.users.tux ? unfree);
        expected = true;
      }
    );

  };
}
