{ den, inputs, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  imports = [ inputs.devshell.flakeModule ];
  den.classes.devshell = { };
  den.schema.flake-parts.policies.to-flake-parts-system-devshell = _: [
    (resolve.to "flake-parts-system" {
      fromClass = "devshell";
      intoPath = [
        "devshells"
        "default"
      ];
    })
  ];
}
