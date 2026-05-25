# Regression: two den.homes on different systems with the same user name both
# default intoAttr to ["homeConfigurations" name]. Previously lib.recursiveUpdate
# silently merged two unrelated module-system evaluations, mixing Linux/Darwin
# paths and causing stack overflow. Fix: auto-qualify colliding output names
# with @system so both are accessible.
{ denTest, ... }:
{
  flake.tests.home-intoattr-collision = {

    # Same user on two systems: should produce system-qualified names.
    test-multi-system-qualified = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.homes.aarch64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];

        expr = builtins.sort (a: b: a < b) (builtins.attrNames config.flake.homeConfigurations);
        expected = [
          "tux@aarch64-linux"
          "tux@x86_64-linux"
        ];
      }
    );

    # Each qualified entry should have the correct system's pkgs.
    test-multi-system-correct-pkgs = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.homes.aarch64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];

        expr = config.flake.homeConfigurations."tux@x86_64-linux".config.nixpkgs.system;
        expected = "x86_64-linux";
      }
    );

    # Single system should keep plain name (no qualification needed).
    test-single-system-plain = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];

        expr = builtins.attrNames config.flake.homeConfigurations;
        expected = [ "tux" ];
      }
    );

    # Manual intoAttr override should still work.
    test-disambiguated-intoattr = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.homes.aarch64-linux.tux = {
          intoAttr = [
            "homeConfigurations"
            "tux-aarch64"
          ];
        };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];

        expr = builtins.attrNames config.flake.homeConfigurations;
        expected = [
          "tux"
          "tux-aarch64"
        ];
      }
    );

  };
}
