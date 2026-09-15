{ den, lib, ... }:
let
  inherit (den.lib.aspects) mkAspectsType;

  # Keys the namespace container owns — everything else freeform is an aspect.
  # Kept in step with modules/aspect-schema.nix's namespace-key filter.
  structuralKeys = [
    "stages"
    "schema"
    "classes"
    "_module"
    "_"
  ];

  namespaceType = lib.types.submodule (
    { name, config, ... }:
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
      # Namespace-root provides bundle, mirroring an aspect's `_`. A namespace
      # root is a container, not an aspect, so it has no provides of its own;
      # here `_` is a synthetic aggregate aspect whose includes are every
      # aspect declared in the namespace. Including it (`[ ns._ ]`) pulls them
      # all in, the container-level analog of `den.aspects.foo._`.
      options._ = lib.mkOption {
        description = "Bundle of every aspect in this namespace; include to pull them all.";
        readOnly = true;
        type = lib.types.raw;
        default = {
          includes = map (k: config.${k}) (
            builtins.filter (k: !builtins.elem k structuralKeys) (builtins.attrNames config)
          );
        };
      };
      freeformType = (mkAspectsType { origin = [ name ]; }).aspectsType;
    }
  );
in
{
  inherit namespaceType;
}
