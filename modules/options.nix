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
      options.parentPath = lib.mkOption {
        description = ''
          For a class whose members nest inside an enclosing config-owner (e.g.
          home-manager inside a host), a function `name -> path` locating a named
          member within that owner's config — the same route the class's content
          is delivered to. The pipe layer uses it to resolve a producer's config
          at its producing class + scope. null for root classes that own a
          top-level config (nixos, darwin, terranix, …).
        '';
        type = lib.types.nullOr lib.types.raw;
        default = null;
      };
      options.parentArg = lib.mkOption {
        description = ''
          For a nested class, the module argument by which a member reaches the
          enclosing config-owner (home-manager exposes the host config as
          `osConfig`). The pipe layer hands a deferred config-thunk the owner
          config under this name. null for root classes.
        '';
        type = lib.types.nullOr lib.types.str;
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
        # A bare-string (or other non-aspect) element used to reach
        # children.nix's aspect walk unchecked and crash with a raw Nix
        # `expected a set but found a string` from propagateScope's `//` —
        # the aspect tier catches this via providerType's `check`, but this
        # freeform collection has no type to route through, so validate here
        # instead, same as excludes below. Recurses into nested lists:
        # children.nix's processInclude walks nested lists the same way, so a
        # bad leaf at any depth must still be caught, just with a den:
        # message instead of the raw one.
        merge =
          acc: val:
          let
            check =
              v:
              if builtins.isList v then
                map check v
              else if builtins.isAttrs v || lib.isFunction v then
                v
              else
                throw "den: den.schema.<kind>.includes: expected a policy or aspect reference, got ${
                  if builtins.isString v then ''"${v}"'' else builtins.typeOf v
                }";
          in
          acc ++ map check val;
      };
      excludes = {
        default = [ ];
        # Bare-string elements used to be accepted and silently exclude
        # nothing: `identity.key` (nix/lib/aspects/fx/identity.nix) reduces a
        # string to "<anon>", which matches no policy. gen-schema has no
        # per-collection `type` to route this through, so validate here —
        # the same defect at the aspect tier (den.aspects.*.excludes) was
        # fixed by routing it through a type; this is the equivalent
        # declaration-time check for the untyped schema-tier collection.
        merge =
          acc: val:
          acc
          ++ map (
            v:
            if builtins.isAttrs v then
              v
            else
              throw "den: den.schema.<kind>.excludes: expected a policy or aspect reference, got ${
                if builtins.isString v then ''"${v}"'' else builtins.typeOf v
              }"
          ) val;
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
