# nix/lib/entities/_types.nix
#
# Shared helpers for entity type definitions.
# Extracted from nix/lib/types.nix — no new functionality.
{
  lib,
  den,
  ...
}:
let
  strOpt =
    description: default:
    lib.mkOption {
      type = lib.types.str;
      inherit description default;
    };

  # Shared aspect lookup with warning for missing aspects.
  lookupAspect =
    den: config:
    if den.aspects ? ${config.name} then
      den.aspects.${config.name}
    else
      lib.warn "den.aspects.${config.name} not defined — entity gets empty aspect" { };

  # Recursive merge without forcing leaf values. Unlike lib.types.anything this
  # does not inspect values deeply (no mapAttrsRecursiveCond), avoiding infinite
  # recursion when values reference other options (e.g. den.aspects).
  deepMergeAttrs = lib.mkOptionType {
    name = "deepMergeAttrs";
    description = "recursively merged attribute set";
    check = builtins.isAttrs;
    merge = _loc: defs: builtins.foldl' (acc: def: lib.recursiveUpdate acc def.value) { } defs;
  };

  # Single shared production run: imports + per-scope path set from ONE fx.handle.
  # Declared as an option so the module fixpoint memoizes it — every consumer
  # (mainModule, __pathSetByScope) reads the same value, guaranteeing one resolve.
  resolveResultOption =
    den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.raw;
      defaultText = "den.lib.aspects.resolveWithPaths config.class config.resolved";
      default = den.lib.aspects.resolveWithPaths config.class config.resolved;
    };

  # mainModule now derives imports from the shared result (no second run).
  mainModuleOption =
    _den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.deferredModule;
      defaultText = "{ inherit (config.__resolveResult) imports; }";
      default = { inherit (config.__resolveResult) imports; };
    };

  # Per-scope path set for the projected (in-context) hasAspect, RE-KEYED from
  # scope-string to ENTITY IDENTITY (id_hash).
  #
  # The structural walk buckets each node under its scope STRING (`host=…`,
  # `host=…,user=…`). But projected hasAspect is consumed in a DEEPER context —
  # the fleet resolve, where the owner inherits ancestor scopes (`environment=…`)
  # — so a scope-string key can never match the owner's standalone-rooted bucket.
  # An entity's `id_hash` is context-free (kind+name, NOT ancestry) and stable
  # across the standalone-produce and fleet-consume runs, so re-keying by it lets
  # the consumer look up by the consuming entity's OWN id_hash with zero ancestor
  # reconciliation. The root scope's entity is `config` itself (its kind is
  # passed in, since the root scope is seeded without a push-scope record).
  pathSetByScopeOption =
    _den: kind: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.raw;
      defaultText = "config.__resolveResult.pathSetByScope (re-keyed by entity id_hash)";
      default =
        let
          r = config.__resolveResult;
          scopeCtxs = r.scopeContexts or { };
          entityKinds = r.scopeEntityKind or { };
          entityForScope =
            scopeStr:
            let
              k = entityKinds.${scopeStr} or kind;
            in
            (scopeCtxs.${scopeStr} or { }).${k} or config;
        in
        # Fold (not mapAttrs') so that if two scopes share an id_hash — id_hash
        # is parent-blind (kind+name), so same-named siblings under different
        # parents collide — their path sets UNION rather than last-wins. Union
        # over-approximates membership (the safe direction); dropping a bucket
        # would false-negative, the original /persist regression.
        lib.foldl' (
          acc: scopeStr:
          let
            k = (entityForScope scopeStr).id_hash or scopeStr;
          in
          acc // { ${k} = (acc.${k} or { }) // r.pathSetByScope.${scopeStr}; }
        ) { } (builtins.attrNames r.pathSetByScope);
    };

  # Entity kinds from the schema's own kind list (gen-schema _kindNames is
  # sorted and excludes _-prefixed introspection keys), minus the shared
  # `conf` base.
  schemaKinds = builtins.filter (n: n != "conf") (den.schema._kindNames or [ ]);

  # Module injected into entity submodules for resolved aspect and
  # collisionPolicy. Extracted here so host.nix, home.nix, and future entity
  # types all share it. Identity (id_hash) is owned by the schema — supplied
  # by gen-schema's mkInstanceType via mkIdentityModule — not duplicated here.
  resolvedCtxModule =
    kind:
    { config, ... }:
    {
      # Injective scope identity, consumed by fx.pipeline's mkScopeId. Defaults
      # to `name`, which is the registry key for most kinds. A kind that rewrites
      # `name` into something non-unique (home forces it to the bare user name)
      # MUST override this with its registry key, or two such entities collapse
      # onto one pipeline scope and merge each other's content.
      options.__scopeName = lib.mkOption {
        description = "Registry key of this ${kind}, used as its internal identity.";
        internal = true;
        visible = false;
        type = lib.types.str;
        default = config.name;
        defaultText = "config.name";
      };
      options.resolved = lib.mkOption {
        description = "The resolved aspect for this ${kind}.";
        readOnly = true;
        type = lib.types.raw;
        default =
          let
            isContextArg = n: builtins.elem n schemaKinds;
            ctx = lib.filterAttrs (n: v: isContextArg n && v != null) config._module.args // {
              ${kind} = config;
            };
          in
          den.lib.resolveEntity kind ctx;
      };
      options.collisionPolicy = lib.mkOption {
        description = "How to handle collisions between den context args and module-system args.";
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
  # System strings recognized as two-level group keys rather than host names.
  reservedSystems = lib.genAttrs lib.systems.flakeExposed (_: true);

  # Normalize mixed host declarations into canonical two-level form.
  # Two-level entries (key is a system string) pass through.
  # Flat entries (key is a host name) are grouped by their `system` attribute.
  preprocessHosts =
    raw:
    let
      systemGroups = lib.filterAttrs (k: _: reservedSystems ? ${k}) raw;
      directHosts = lib.filterAttrs (k: _: !(reservedSystems ? ${k})) raw;
      grouped = lib.foldlAttrs (
        acc: name: cfg:
        let
          system =
            cfg.system
              or (throw "den: flat host '${name}' must specify 'system' (e.g. system = \"x86_64-linux\")");
        in
        acc
        // {
          ${system} = (acc.${system} or { }) // {
            ${name} = builtins.removeAttrs cfg [ "system" ];
          };
        }
      ) { } directHosts;
    in
    lib.recursiveUpdate systemGroups grouped;
in
{
  inherit
    strOpt
    lookupAspect
    deepMergeAttrs
    mainModuleOption
    resolveResultOption
    pathSetByScopeOption
    resolvedCtxModule
    reservedSystems
    preprocessHosts
    ;
}
