{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.devshell.flakeModule ];
  den.classes.devshell = { };
  den.policies.to-flake-parts-system-devshell = _: [
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
  den.schema.flake-parts.includes = [ den.policies.to-flake-parts-system-devshell ];
}
