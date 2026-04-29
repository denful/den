{ den, lib, ... }:
let
  flakePartsEntity = den.lib.resolveEntity "flake-parts" { };

  perSystemFwd =
    {
      fromClass,
      intoPath ? [ fromClass ],
      ...
    }:
    den.provides.forward {
      each = [ true ];
      fromClass = _: fromClass;
      intoClass = _: "flake-parts";
      intoPath = _: intoPath;
      fromAspect = _: flakePartsEntity;
      adaptArgs = { config, ... }: config.allModuleArgs;
    };

  perSystemModule = den.lib.aspects.resolve "flake-parts" (den.lib.resolveEntity "flake-parts" { });
in
{
  den.schema.flake-parts-system.includes = [ perSystemFwd ];
  perSystem.imports = [ perSystemModule ];
}
