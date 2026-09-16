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

  # Shared aspect lookup: an entity takes EVERY candidate aspect that exists,
  # most specific first, composed through `includes`.
  #
  # NOT "first match wins", and the reason is that existence cannot answer the
  # question a first-match lookup needs to ask. `modules/aspects/definition.nix`
  # registers a stub aspect per entity (`genAttrs classes (_: { })`) so an
  # entity's class keys always exist, which means `den.aspects ? <entity name>`
  # is TRUE for every declared entity whether or not anyone wrote that aspect
  # — measured: a host declared with no aspect at all still answers true. A
  # stub is also structurally indistinguishable from a written aspect (same
  # keys, `name` defaulted from the attr path, no content), so no predicate
  # over `den.aspects` can separate them.
  #
  # Composing sidesteps that entirely: a stub contributes empty class keys, so
  # including one is a no-op, and nothing has to know which is which. It also
  # gives the better semantics — a user's shared aspect and their host-specific
  # one both apply, rather than the qualified one shadowing config the author
  # can still see in their tree.
  #
  # A single present candidate is returned AS ITSELF rather than wrapped, so
  # the overwhelmingly common case keeps its own identity, name and provenance
  # exactly as before this existed.
  lookupAspectBy =
    den: candidates:
    let
      wanted = lib.unique candidates;
      present = builtins.filter (n: den.aspects ? ${n}) wanted;
    in
    if present == [ ] then
      lib.warn
        "den.aspects.${lib.concatStringsSep " / den.aspects." wanted} not defined — entity gets empty aspect"
        { }
    else if builtins.length present == 1 then
      den.aspects.${builtins.head present}
    else
      {
        # Angle-bracketed so den's own synthetic-name handling applies, and
        # carrying the candidates so two entities composing different pairs
        # cannot collide on one identity.
        name = "<aspects:${lib.concatStringsSep "+" present}>";
        includes = map (n: den.aspects.${n}) present;
      };

  # Single-candidate form, for a kind whose registry key is its only spelling.
  lookupAspect = den: config: lookupAspectBy den [ config.name ];

  # Recursive merge without forcing leaf values. Unlike lib.types.anything this
  # does not inspect values deeply (no mapAttrsRecursiveCond), avoiding infinite
  # recursion when values reference other options (e.g. den.aspects).
  # Concatenates lists rather than overwriting them, which `lib.recursiveUpdate`
  # does because it treats a list as an opaque leaf. Two files each writing
  # `den.hosts.<h>.includes` therefore kept one list and dropped the other in
  # silence, while an attrset key under the same two definitions merged
  # normally (measured: `users.alice` and `users.bob` both survive).
  #
  # Concatenation is the module system's own rule for a list-valued option
  # (`listOf` merges by `concatLists`) and den's rule at the aspect tier
  # (`aspectContentType`'s `deepMerge`), so this makes the entity registry
  # agree with both rather than introduce a third behaviour. It matters most
  # for the collection keys: `includes`, `excludes` and `classes` are the
  # list-valued keys an entity carries, and all three accumulate everywhere
  # else they appear.
  # A value the module system would have merged by equality had the key been
  # declared. Functions and derivations are excluded: `==` on two functions is
  # always false, so comparing them would refuse two identical definitions.
  isPlainScalar =
    v:
    builtins.elem (builtins.typeOf v) [
      "string"
      "int"
      "bool"
      "float"
      "null"
    ];

  # Values named by type, with the value itself only where rendering it is
  # safe. `builtins.toJSON` on a derivation or a function throws, and one side
  # of a conflict can be either, so a message that always rendered both would
  # fail while reporting a failure.
  show =
    v: if isPlainScalar v then "`${builtins.toJSON v}`" else "a value of type ${builtins.typeOf v}";

  deepMergeAttrs = lib.mkOptionType {
    name = "deepMergeAttrs";
    description = "recursively merged attribute set";
    check = builtins.isAttrs;
    merge =
      _loc: defs:
      let
        merge2 =
          a: b:
          a
          // builtins.mapAttrs (
            bk: bv:
            if !(a ? ${bk}) then
              bv
            else if builtins.isAttrs a.${bk} && builtins.isAttrs bv then
              merge2 a.${bk} bv
            else if builtins.isList a.${bk} && builtins.isList bv then
              # `bv` first: defs reach this merge in reverse declaration order,
              # so `a` holds the LATER definition. Measured, not assumed, and
              # it is the same ordering that makes the scalar arm below read as
              # first-declaration-wins.
              bv ++ a.${bk}
            else if
              # Either side a plain scalar means the two are not both mergeable
              # shapes, so reaching here with different values is a genuine
              # conflict: two scalars that differ, or a type mismatch such as a
              # list against a string. Both silently resolved to one definition
              # before this.
              (isPlainScalar a.${bk} || isPlainScalar bv) && a.${bk} != bv
            then
              throw ''
                den: conflicting definitions for `${bk}` on an entity.

                ${show bv} and ${show a.${bk}} were both defined, and neither is a shape the other merges with. Attribute sets merge and lists concatenate; everything else has to agree.

                Remove one definition, or give the two a key each.
              ''
            else
              bv
          ) b;
      in
      builtins.foldl' (acc: def: merge2 acc def.value) { } defs;
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
    lookupAspectBy
    deepMergeAttrs
    mainModuleOption
    resolveResultOption
    pathSetByScopeOption
    resolvedCtxModule
    reservedSystems
    preprocessHosts
    ;
}
