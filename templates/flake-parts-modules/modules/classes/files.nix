{ den, inputs, ... }:
let
  inherit (den.lib.policy) route;
in
{
  imports = [ inputs.files.flakeModules.default ];
  den.classes.files = { };
  den.policies.to-flake-parts-system-files = _: [
    (route {
      fromClass = "files";
      intoClass = "flake-parts";
      path = [ "files" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
  den.schema.flake-parts.includes = [ den.policies.to-flake-parts-system-files ];
}
