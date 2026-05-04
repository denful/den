{ den, lib, ... }:
let
  inherit (den.lib.aspects) mkAspectsType;

  namespaceType = lib.types.submodule (
    { name, ... }:
    {
      options.schema = lib.mkOption {
        description = "namespace schema — freeform deferred modules per entity kind";
        defaultText = lib.literalExpression "{ }";
        default = { };
        type = lib.types.submodule {
          freeformType = lib.types.lazyAttrsOf lib.types.deferredModule;
        };
      };
      options.classes = lib.mkOption {
        description = "class declarations merged into den.classes on import";
        defaultText = lib.literalExpression "{ }";
        default = { };
        type = lib.types.lazyAttrsOf lib.types.raw;
      };
      freeformType = (mkAspectsType { providerPrefix = [ name ]; }).aspectsType;
    }
  );
in
{
  inherit namespaceType;
}
