{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (config) den;
  types = import ./../nix/lib/types.nix {
    inherit
      inputs
      lib
      den
      config
      ;
  };
  # Imported directly, not via den.lib.schema: this declares options.den.schema,
  # and den.lib's map includes schema-util which reads den.schema._kindNames —
  # routing through den.lib here would close that cycle. Entity types consume it
  # lazily at eval time, so they safely use den.lib.schema.
  schemaLib = import ./../nix/lib/schema.nix { inherit inputs lib; };

  classSchemaType = lib.types.submodule (
    { ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this class domain.";
        type = lib.types.str;
      };
      options.forwardTo = lib.mkOption {
        description = "Optional forward target for class evaluation.";
        type = lib.types.nullOr lib.types.raw;
        default = null;
      };
    }
  );

  pipeSchemaType = lib.types.submodule (
    { ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this pipe.";
        type = lib.types.str;
      };
    }
  );
in
{
  options.den.hosts = types.hostsOption;
  options.den.homes = types.homesOption;
  options.den.schema = schemaLib.mkSchemaOption {
    collections = {
      includes = {
        default = [ ];
      };
      excludes = {
        default = [ ];
      };
      isEntity = {
        default = false;
        merge = acc: val: acc || val;
      };
      isolated = {
        default = false;
        merge = acc: val: acc || val;
      };
    };
    computed = collections: defs: {
      isEntity =
        collections.isEntity
        || builtins.any (
          d:
          let
            v = d.value;
            collectionKeys = [
              "includes"
              "excludes"
              "isEntity"
              "isolated"
              "parent"
              "collisionPolicy"
            ];
            stripped = if builtins.isAttrs v then builtins.removeAttrs v collectionKeys else v;
          in
          !builtins.isAttrs stripped || stripped != { }
        ) defs;
    };
  };
  # Built-in entity topology: users nest inside hosts, homes nest inside hosts.
  config.den.schema.user.parent = "host";
  config.den.schema.home.parent = "host";

  options.den.reservedKeys = lib.mkOption {
    description = "Additional aspect keys reserved from pipeline dispatch. These keys are treated as structural — the pipeline ignores them, letting consumers use them for metadata.";
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [
      "settings"
      "tags"
    ];
  };

  options.den.classes = lib.mkOption {
    description = "Class evaluation domains";
    type = lib.types.lazyAttrsOf classSchemaType;
    default = { };
  };
  options.den.quirks = lib.mkOption {
    description = "Quirk declarations — named data routes for structured quirk flow";
    type = lib.types.lazyAttrsOf pipeSchemaType;
    default = { };
    apply =
      quirks:
      let
        classKeys = builtins.attrNames (den.classes or { });
        overlap = builtins.filter (k: builtins.elem k classKeys) (builtins.attrNames quirks);
      in
      assert
        overlap == [ ]
        || throw "den.classes and den.quirks must not share keys, but found: ${builtins.concatStringsSep ", " overlap}";
      lib.mapAttrs (name: v: v // { inherit name; }) quirks;
  };
  config.den.schema.conf = { };
  config.den.schema.fleet = { };
  config.den.schema.host.imports = [ den.schema.conf ];
  config.den.schema.user.imports = [ den.schema.conf ];
  config.den.schema.home.imports = [ den.schema.conf ];
  config.den.classes = {
    nixos.description = "NixOS system configuration";
    darwin.description = "nix-darwin system configuration";
  };
}
