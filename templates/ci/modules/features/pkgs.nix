{ denTest, ... }:
{
  flake.tests.pkgs = {

    test-pkgs-set-on-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ (den.batteries.pkgs (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: (builtins.head (builtins.splitVersion pkg.name))) igloo.environment.systemPackages);
        expected = true;
      }
    );

    test-pkgs-set-on-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den.batteries.pkgs (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: pkg.pname) igloo.users.users.tux.packages);
        expected = true;
      }
    );

    test-pkgs-set-on-home-manager = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [ (den.batteries.pkgs (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: (builtins.head (builtins.splitVersion pkg.name))) tuxHm.home.packages);
        expected = true;
      }
    );

    test-pkgs-to-host-set-on-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den.batteries.pkgs.to-host (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: (builtins.head (builtins.splitVersion pkg.name))) igloo.environment.systemPackages);
        expected = true;
      }
    );

    test-pkgs-to-user-set-on-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den.batteries.pkgs.to-user (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: pkg.pname) igloo.users.users.tux.packages);
        expected = true;
      }
    );

    test-pkgs-to-home-set-on-home-manager = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [ (den.batteries.pkgs.to-home (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: (builtins.head (builtins.splitVersion pkg.name))) tuxHm.home.packages);
        expected = true;
      }
    );

    test-pkgs-set-on-user-not-on-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den.batteries.pkgs (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: (builtins.head (builtins.splitVersion pkg.name))) igloo.environment.systemPackages);
        expected = false;
      }
    );

    test-pkgs-set-on-home-manager-not-on-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.default.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [ (den.batteries.pkgs (pkgs: [pkgs.hello])) ];

        expr = builtins.elem "hello" (builtins.map (pkg: pkg.pname) igloo.users.users.tux.packages);
        expected = false;
      }
    );

  };
}
