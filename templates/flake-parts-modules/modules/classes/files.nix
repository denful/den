{ den, inputs, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  imports = [ inputs.files.flakeModules.default ];
  den.classes.files = { };
  den.schema.flake-parts.policies.to-flake-parts-system-files = _: [
    (resolve.to "flake-parts-system" { fromClass = "files"; })
  ];
}
