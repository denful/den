{
  den,
  inputs,
  config,
  ...
}:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.nix-unit.modules.flake.default ];
  den.classes.tests = { };

  # some globals
  perSystem.nix-unit = {
    allowNetwork = true;
    inputs = inputs;
  };

  den.policies.tests-to-flake-parts = _: [
    (route {
      fromClass = "tests";
      intoClass = "flake-parts";
      collectSubtree = true;
      path = [
        "nix-unit"
        "tests"
      ];
      # test helpers
      adaptArgs =
        args:
        let
          igloo = config.flake.nixosConfigurations.igloo.config;
          tux = igloo.users.users.tux;
        in
        args.config.allModuleArgs // { inherit igloo tux; };
    })
  ];
  den.schema.flake-parts.includes = [ den.policies.tests-to-flake-parts ];
}
