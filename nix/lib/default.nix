{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (config) den;
  load =
    f:
    import f {
      inherit
        lib
        config
        inputs
        den
        den-lib
        ;
    };
  den-lib = builtins.mapAttrs (_: load) {
    aspects = ./aspects;
    canTake = ./can-take.nix;
    __findFile = ./den-brackets.nix;
    forward = ./forward.nix;
    home-env = ./home-env.nix;
    nh = ./nh.nix;
    nixModule = ../nixModule;
    nsTypes = ./namespace-types.nix;
    parametric = ./parametric.nix;
    take = ./take.nix;
    policyTypes = ./policy-types.nix;
    resolveStage = ./resolve-stage.nix;
    stageTypes = ./stage-types.nix;
    strict = ./strict.nix;
    policyInspect = ./policy-inspect.nix;
    synthesizePolicies = ./synthesize-policies.nix;
    fx = ./fx.nix;
  };
in
den-lib
