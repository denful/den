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
    acceptance = ./acceptance.nix;
    argsName = ./args-name.nix;
    aspects = ./aspects;
    canTake = ./can-take.nix;
    __findFile = ./den-brackets.nix;
    forward = ./forward.nix;
    enforcement = ./enforcement.nix;
    home-env = ./home-env.nix;
    migrations = ./migrations.nix;
    nh = ./nh.nix;
    nixModule = ../nixModule;
    nsTypes = ./namespace-types.nix;
    parametric = ./parametric.nix;
    take = ./take.nix;
    policy = ./policy-effects.nix;
    resolveEntity = ./resolve-entity.nix;
    strict = ./strict.nix;
    capture = ./diag/capture.nix;
    policyInspect = ./policy-inspect.nix;
    schemaUtil = ./schema-util.nix;
    synthesizePolicies = ./synthesize-policies.nix;
    fx = ./fx.nix;
    schema = ./schema.nix;
  };
in
den-lib
