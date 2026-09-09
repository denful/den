# PERFORMANCE SUITE COVERAGE — read this before trusting `perf 31/31`.
#
# Every OTHER file feeding `flake.tests.performance` (resolve.nix, depth.nix,
# forward.nix, namespace.nix, ctx-pipeline.nix, ctx-chain.nix, pure-eval.nix,
# deprecated/parametric.nix) resolves a bare `den.aspects.<name>` tree via
# `funnyNames`/`den.lib.resolveEntity` directly. None of them declares a
# `den.hosts` or `den.homes` entity, so none builds a real
# nixosConfiguration/homeConfiguration or runs the schema/policy dispatch
# that only fires at entity scope (den.schema.host.includes,
# den.classes.homeManager parent-path forwarding, etc). A green suite there
# certifies the aspect-resolution walk, not entity or fleet building.
#
# This file and fleet-scale.nix close that gap:
#   - test-entity-chain-host-user-home (below): one host, one host-nested
#     user, one standalone home, each carrying its own N-deep includes
#     chain through a REAL class (nixos/homeManager), forcing an actual
#     nixosConfiguration + home-manager user + homeConfiguration build.
#   - fleet-scale.nix: N hosts built and forced individually, N configurable.
#
# What is still NOT covered: timing/cost assertions. nix-unit asserts
# correctness, not wall-clock; D4 (fleet-linear policy dispatch,
# nix/lib/aspects/fx/handlers/constraint.nix `isPolicyExcluded`) needs a
# real timing comparison (`just bench`, external), not a cell here — these
# cells only make the entity/fleet scale D4 depends on reachable by CI.
{ denTest, lib, ... }:
let
  mkNixosChain =
    n:
    let
      go =
        i:
        if i >= n then
          { nixos.environment.etc."chain-leaf".text = "leaf"; }
        else
          {
            nixos.environment.etc."chain-${toString i}".text = "n${toString i}";
            includes = [ (go (i + 1)) ];
          };
    in
    go 0;

  mkHmChain =
    n:
    let
      go =
        i:
        if i >= n then
          { homeManager.home.sessionVariables.CHAIN_LEAF = "leaf"; }
        else
          {
            homeManager.home.sessionVariables."CHAIN_${toString i}" = "n${toString i}";
            includes = [ (go (i + 1)) ];
          };
    in
    go 0;

  # depth of each entity's own chain — a single entity per class, not
  # fleet-multiplied, so this can run deeper than fleet-scale.nix's N.
  n = 20;
in
{
  flake.tests.performance.entity = {

    test-entity-chain-host-user-home = denTest (
      {
        den,
        igloo,
        tuxHm,
        config,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.solo = { };
        # define-user supplies home.username/homeDirectory for both the
        # host-nested user and the standalone home — required to force
        # standalone .config without an assertion failure (see homes.nix).
        den.default.includes = [ den.provides.define-user ];

        den.aspects.igloo = mkNixosChain n;
        den.aspects.tux.includes = [ (mkHmChain n) ];
        den.aspects.solo.includes = [ (mkHmChain n) ];

        expr = {
          hostChainLen = builtins.length (
            lib.filter (k: lib.hasPrefix "chain-" k) (builtins.attrNames igloo.environment.etc)
          );
          userChainLen = builtins.length (
            lib.filter (k: lib.hasPrefix "CHAIN_" k) (builtins.attrNames tuxHm.home.sessionVariables)
          );
          homeChainLen = builtins.length (
            lib.filter (k: lib.hasPrefix "CHAIN_" k) (
              builtins.attrNames config.flake.homeConfigurations.solo.config.home.sessionVariables
            )
          );
        };
        expected = {
          hostChainLen = n + 1;
          userChainLen = n + 1;
          homeChainLen = n + 1;
        };
      }
    );

  };
}
