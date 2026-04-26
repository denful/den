{ den, lib, ... }:
let
  inherit (den.lib.aspects) mkAspectsType;
  inherit (den.lib.stageTypes) stageTreeType;

  namespaceType = lib.types.submodule (
    nsArgs@{ name, ... }:
    {
      options.stages = lib.mkOption {
        description = "namespace stage scopes";
        defaultText = lib.literalExpression "{ }";
        default = { };
        type = lib.types.lazyAttrsOf stageTreeType;
      };
      options.schema = lib.mkOption {
        description = "namespace schema — freeform deferred modules per entity kind";
        defaultText = lib.literalExpression "{ }";
        default = { };
        type = lib.types.submodule {
          freeformType = lib.types.lazyAttrsOf lib.types.deferredModule;
        };
      };
      options.traits = lib.mkOption {
        description = "trait declarations merged into den.schema.traits on import";
        defaultText = lib.literalExpression "{ }";
        default = { };
        type = lib.types.lazyAttrsOf lib.types.raw;
      };
      options.classes = lib.mkOption {
        description = "class declarations merged into den.schema.classes on import";
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
