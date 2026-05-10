{ lib, config, ... }:
{
  options.den = lib.mkOption {
    type = lib.types.submodule {
      imports = [
        (lib.mkAliasOptionModule [ "provides" ] [ "batteries" ])
        (lib.mkAliasOptionModule [ "_" ] [ "batteries" ])
      ];
      options.batteries = lib.mkOption {
        defaultText = lib.literalExpression "{ }";
        default = { };
        description = "Batteries Included - re-usable high-level aspects";
        type = lib.types.submodule {
          freeformType = lib.types.attrsOf (
            (config.den.lib.aspects.mkAspectsType {
              providerPrefix = [
                "den"
                "batteries"
              ];
            }).providerType
          );
        };
      };
    };
  };
}
