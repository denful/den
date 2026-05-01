{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.files.flakeModules.default ];
  den.classes.files = { };
  den.schema.flake-parts.policies.to-flake-parts-system-files = _: [
    (route {
      fromClass = "files";
      intoClass = "flake-parts";
      path = [ "files" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
}
