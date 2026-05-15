{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.devshell.flakeModule ];
  den.classes.devshell = { };
  den.policies.devshell-to-flake-parts = _: [
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
  den.schema.flake-parts.includes = [ den.policies.devshell-to-flake-parts ];
}
