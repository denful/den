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

  # Context args are derived from the entity's _module.args, filtered to
  # known entity kinds so framework args don't leak through.
  schemaKinds = builtins.filter (n: n != "conf" && !(lib.hasPrefix "_" n)) (
    builtins.attrNames (den.schema or { })
  );
  knownKinds = lib.unique (
    schemaKinds ++ builtins.attrNames ((den.entityIncludes or { }) // (den.entityProvides or { }))
  );

  # Option type names whose values are safe for identity hashing.
  primitiveTypeNames = [
    "str"
    "int"
    "bool"
  ];

  schemaEntryType =
    let
      base = lib.types.deferredModule;
    in
    base
    // {
      merge =
        loc: defs:
        let
          kind = lib.last loc;
          # Extract includes from defs that have them, strip before deferred merge
          allIncludes = lib.concatMap (
            d:
            if builtins.isAttrs d.value && d.value ? includes && builtins.isList d.value.includes then
              d.value.includes
            else
              [ ]
          ) defs;
          strippedDefs = map (
            d:
            if builtins.isAttrs d.value && d.value ? includes && builtins.isList d.value.includes then
              d // { value = builtins.removeAttrs d.value [ "includes" ]; }
            else
              d
          ) defs;
          merged = base.merge loc strippedDefs;

          resolvedCtx =
            { config, options, ... }:
            {
              # Stable identity hash for entity comparison.
              #
              # Nix's `==` does deep structural comparison which diverges or
              # infinitely recurses when the same entity is accessed via
              # different module system thunks. This hash reflects on all
              # non-internal primitive options (str, int, bool), prefixed by
              # schema kind, to produce a cheap string identity.
              #
              # Automatically includes any primitive option declared on the
              # entity — custom entity types get this for free.
              #
              # Usage: builtins.filter (h: h.id_hash != host.id_hash) allHosts
              options.id_hash = lib.mkOption {
                description = ''
                  Auto-computed identity hash for entity comparison.

                  Derived by reflecting on all non-internal, primitive-typed
                  options (str, int, bool) declared on this entity. The schema
                  kind is included to prevent cross-kind collisions.

                  Use `a.id_hash != b.id_hash` instead of `a != b` for entity
                  comparison — Nix's `==` does deep structural comparison which
                  is fragile across module system boundaries.
                '';
                readOnly = true;
                internal = true;
                type = lib.types.str;
                default =
                  let
                    isPrimitive =
                      _: opt:
                      (opt ? type) && builtins.elem (opt.type.name or "") primitiveTypeNames && !(opt.internal or false);
                    identityKeys = lib.sort (a: b: a < b) (builtins.attrNames (lib.filterAttrs isPrimitive options));
                    encode =
                      k:
                      let
                        v = config.${k};
                      in
                      "${k}=${toString v}";
                    fingerprint = "${kind}|${lib.concatMapStringsSep "|" encode identityKeys}";
                  in
                  builtins.hashString "sha256" fingerprint;
              };
              options.resolved = lib.mkOption {
                description = "The resolved aspect for this ${kind}.";
                readOnly = true;
                type = lib.types.raw;
                default =
                  let
                    # knownKinds already includes schema-derived kinds.
                    isContextArg = n: builtins.elem n knownKinds;
                    ctx = lib.filterAttrs (n: v: isContextArg n && v != null) config._module.args // {
                      ${kind} = config;
                    };
                  in
                  den.lib.resolveEntity kind ctx;
              };
              options.collisionPolicy = lib.mkOption {
                description = "How to handle collisions between den context args and module-system args in flat-form class modules.";
                type = lib.types.nullOr (
                  lib.types.enum [
                    "error"
                    "class-wins"
                    "den-wins"
                  ]
                );
                default = null;
              };
            };
          # Entity gating: kind gets pipeline wiring if it has includes OR entityIncludes (backward compat)
          hasEntityContent =
            allIncludes != [ ]
            || (den.entityIncludes or { }) ? ${kind}
            || (den.entityProvides or { }) ? ${kind};
          # A schema entry is "structural" if it has module content beyond just includes.
          # Only structural entries should get self-provide aspect lookup.
          hasStructuralContent = builtins.any (
            d:
            let
              v = d.value;
              stripped =
                if builtins.isAttrs v && v ? includes && builtins.isList v.includes then
                  builtins.removeAttrs v [ "includes" ]
                else
                  v;
            in
            !builtins.isAttrs stripped || stripped != { }
          ) defs;
        in
        if hasEntityContent then
          {
            __functor =
              _:
              { ... }:
              {
                imports = [
                  merged
                  resolvedCtx
                ];
              };
            includes = allIncludes;
            isEntity = hasStructuralContent;
          }
        else
          {
            __functor = _: { ... }: merged;
            includes = [ ];
            isEntity = false;
          };
    };

  classSchemaType = lib.types.submodule (
    { name, ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this class domain.";
        type = lib.types.str;
        apply =
          v:
          if (den.traits or { }) ? ${name} then
            throw "den: '${name}' cannot be both a class and a trait"
          else
            v;
      };
      options.forwardTo = lib.mkOption {
        description = "Optional forward target for class evaluation.";
        type = lib.types.nullOr lib.types.raw;
        default = null;
      };
    }
  );

  traitSchemaType = lib.types.submodule (
    { name, ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this trait channel.";
        type = lib.types.str;
        apply =
          v:
          if (den.classes or { }) ? ${name} then
            throw "den: '${name}' cannot be both a class and a trait"
          else
            v;
      };
      options.collection = lib.mkOption {
        description = "Collection strategy for trait data.";
        type = lib.types.enum [
          "list"
          "map"
        ];
        default = "list";
      };
      options.partialOk = lib.mkOption {
        description = "Whether partial trait data is acceptable.";
        type = lib.types.bool;
        default = false;
      };
      options.type = lib.mkOption {
        description = "Optional type constraint for trait values.";
        type = lib.types.nullOr lib.types.raw;
        default = null;
      };
    }
  );

  # Collision check lives in each schema type's description `apply`
  # function rather than the outer type merge. This keeps the check
  # lazy — it only fires when `.description` of a colliding key is
  # accessed, avoiding circular evaluation between den.classes/den.traits.

  schemaOption = lib.mkOption {
    description = "freeform deferred modules per entity kind";
    defaultText = lib.literalExpression "{ }";
    default = { };
    type = lib.types.submodule {
      freeformType = lib.types.lazyAttrsOf schemaEntryType;
    };
  };
in
{
  options.den.hosts = types.hostsOption;
  options.den.homes = types.homesOption;
  options.den.schema = schemaOption;
  options.den.classes = lib.mkOption {
    description = "Class evaluation domains";
    type = lib.types.lazyAttrsOf classSchemaType;
    default = { };
  };
  options.den.traits = lib.mkOption {
    description = "Trait semantic data channels";
    type = lib.types.lazyAttrsOf traitSchemaType;
    default = { };
  };
  config.den.schema = {
    conf = { };
    host.imports = [ den.schema.conf ];
    user.imports = [ den.schema.conf ];
    home.imports = [ den.schema.conf ];
  };
  config.den.classes = {
    nixos.description = "NixOS system configuration";
    darwin.description = "nix-darwin system configuration";
  };
}
