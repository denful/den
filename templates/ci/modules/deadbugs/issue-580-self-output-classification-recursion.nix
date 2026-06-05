# Regression for #580: infinite recursion when an UNREGISTERED aspect key
# consumes a flake self-output (`self.outputs.*`).
#
# Reproduction: https://github.com/musjj/recursion-bug
#   den.default.nixpkgs.overlays = builtins.attrValues self.outputs.overlays;
#
# Root cause — key-classification.nix `hasRecognizedSubKeys`:
# to decide whether an unregistered key (here `nixpkgs`) is a nested aspect,
# it inspects each sub-key with `builtins.isAttrs (val.${sk} or null)`, which
# FORCES the sub-key's value to WHNF.  Classification runs while the flake
# output set is still being assembled, so forcing a value that reads
# `self.outputs` re-enters the flake `self` fixpoint → infinite recursion.
#
# Registered class keys (nixos/darwin/homeManager) bypass `isNestedKey`
# entirely, so their content stays lazy until NixOS-module build time (after
# the `self` fixpoint has resolved) — they never trigger the cycle.  This is
# why the bug is invisible for normal class content and only bites
# unregistered keys like `nixpkgs`.  The forwarder / homeManager user in the
# original report were incidental — neither is required to trigger it.
#
# `config.flake` is the in-harness analogue of `self.outputs`.
{ denTest, ... }:
{
  flake.tests.issue-580-self-output-classification-recursion = {

    # The bug: unregistered `nixpkgs` key whose value reads a flake
    # self-output.  Classification forces the value → self-fixpoint cycle.
    test-unregistered-key-self-output = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default = {
          nixpkgs.overlays = builtins.attrValues (config.flake.nixosConfigurations or { });
          nixos.networking.hostName = "no-recursion";
        };

        expr = igloo.networking.hostName;
        expected = "no-recursion";
      }
    );

    # Contrast / boundary guard: the SAME self-output reference under a
    # registered class key stays lazy and evaluates fine.  Proves the cycle
    # is specific to unregistered-key classification, and guards against a
    # fix that over-corrects by forcing registered content too.
    test-registered-key-self-output = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default = {
          nixos.networking.hostName = "ok-${
            toString (builtins.length (builtins.attrValues (config.flake.nixosConfigurations or { })))
          }";
          nixos.users.users.tux.isNormalUser = true;
        };

        expr = igloo.networking.hostName;
        expected = "ok-1";
      }
    );

  };
}
