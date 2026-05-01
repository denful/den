{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.devshell.flakeModule ];
  den.classes.devshell = { };
  den.schema.flake-parts.policies.to-flake-parts-system-devshell = _: [
    (route {
      fromClass = "devshell";
      intoClass = "flake-parts";
      path = [
        "devshells"
        "default"
      ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
}
