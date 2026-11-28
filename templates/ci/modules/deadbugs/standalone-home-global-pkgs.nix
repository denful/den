# A standalone `user@host` home on a declared host builds its own nixpkgs
# (`home.pkgs`), so den's unfree and insecure predicates belong on it even when
# the host sets `home-manager.useGlobalPkgs`: that setting is about the host's
# nested homes, which share the host's nixpkgs and get the predicates there.
{ denTest, ... }:
let
  base =
    { den, ... }:
    {
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [ den.provides.define-user ];
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.tux.includes = [
        (den.provides.unfree [ "vscode" ])
        (den.batteries.insecure [ "olm-3.2.16" ])
      ];
    };
  globalPkgs = v: { den.aspects.igloo.nixos.home-manager.useGlobalPkgs = v; };
  predicates = hm: {
    unfree = (hm.nixpkgs.config.allowUnfreePredicate or (_: false)) { pname = "vscode"; };
    insecure = builtins.elem "olm-3.2.16" (hm.nixpkgs.config.permittedInsecurePackages or [ ]);
  };
  home = config: name: config.flake.homeConfigurations.${name}.config;
in
{
  flake.tests.standalone-home-global-pkgs = {

    # The reported case: igloo nests tux with useGlobalPkgs, and the standalone
    # `tux@igloo` home builds its own nixpkgs.
    test-standalone-home-on-global-pkgs-host = denTest (
      { config, ... }:
      {
        imports = [
          base
          (globalPkgs true)
        ];
        den.homes.x86_64-linux."tux@igloo" = { };
        expr = predicates (home config "tux@igloo");
        expected = {
          unfree = true;
          insecure = true;
        };
      }
    );

    # Control: the nested home shares the host's nixpkgs, so the predicates
    # are on the host, not on the home, as before.
    test-nested-home-on-global-pkgs-host = denTest (
      { tuxHm, igloo, ... }:
      {
        imports = [
          base
          (globalPkgs true)
        ];
        expr = {
          home = predicates tuxHm;
          host = predicates { inherit (igloo) nixpkgs; };
        };
        expected = {
          home = {
            unfree = false;
            insecure = false;
          };
          host = {
            unfree = true;
            insecure = true;
          };
        };
      }
    );

    # Control: a nested home on a host without useGlobalPkgs builds its own
    # nixpkgs, so the predicates are on the home.
    test-nested-home-on-own-pkgs-host = denTest (
      { tuxHm, ... }:
      {
        imports = [
          base
          (globalPkgs false)
        ];
        expr = predicates tuxHm;
        expected = {
          unfree = true;
          insecure = true;
        };
      }
    );

    # Control: a host without useGlobalPkgs.
    test-standalone-home-on-own-pkgs-host = denTest (
      { config, ... }:
      {
        imports = [
          base
          (globalPkgs false)
        ];
        den.homes.x86_64-linux."tux@igloo" = { };
        expr = predicates (home config "tux@igloo");
        expected = {
          unfree = true;
          insecure = true;
        };
      }
    );

    # Control: a standalone home on a host den doesn't declare.
    test-standalone-home-on-undeclared-host = denTest (
      { config, den, ... }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];
        den.homes.x86_64-linux."ann@elsewhere" = { };
        den.aspects.ann.includes = [
          (den.provides.unfree [ "vscode" ])
          (den.batteries.insecure [ "olm-3.2.16" ])
        ];
        expr = predicates (home config "ann@elsewhere");
        expected = {
          unfree = true;
          insecure = true;
        };
      }
    );
  };
}
