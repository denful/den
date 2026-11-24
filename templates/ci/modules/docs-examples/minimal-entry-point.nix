# The example in docs/src/content/docs/guides/from-zero-to-den.mdx ("The smallest Den").
# The guide reads nixpkgs' eval-config.nix from the reader's channel (`<nixpkgs>`). CI has no
# NIX_PATH, so this cell takes the same file from the flake's nixpkgs input.
{ denTest, inputs, ... }:
let
  # `system = null` because this runs under pure evaluation, where eval-config's default,
  # `builtins.currentSystem`, is missing; the guide's impure setup needs no override. Either way
  # the platform comes from the host's `nixpkgs.hostPlatform`, which den sets from
  # `den.hosts.<system>` (test-platform-from-host).
  evalConfig =
    args: import (inputs.nixpkgs + "/nixos/lib/eval-config.nix") (args // { system = null; });
in
{
  flake.tests.docs-minimal-entry-point = {
    test-instantiate-with-eval-config = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.instantiate = evalConfig;
        den.aspects.igloo.nixos =
          { pkgs, ... }:
          {
            environment.systemPackages = [ pkgs.hello ];
          };
        expr = builtins.any (p: (p.pname or "") == "hello") igloo.environment.systemPackages;
        expected = true;
      }
    );
    test-platform-from-host = denTest (
      { den, config, ... }:
      {
        den.hosts.aarch64-linux.igloo.instantiate = evalConfig;
        expr = config.flake.nixosConfigurations.igloo.pkgs.stdenv.hostPlatform.system;
        expected = "aarch64-linux";
      }
    );
    test-instantiate-is-used = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.instantiate = args: evalConfig args // { builtByEvalConfig = true; };
        expr = config.flake.nixosConfigurations.igloo.builtByEvalConfig or false;
        expected = true;
      }
    );
  };
}
