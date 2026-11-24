{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (config) den;
  inherit (import ./../nix/lib/migrations.nix { inherit config; }) removalDate;
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
  schemaLib = import ./../nix/lib/schema.nix { inherit inputs lib den; };
  strictEntry = import ./../nix/lib/strict.nix { };

  # Element check for BOTH schema-tier collections. gen-schema has no
  # per-collection `type` to route a bad element through, so the check that the
  # aspect tier gets from `providerType` has to live here — and it has to be
  # ONE check: the two collections take the same references, so a shape that
  # excludes at the aspect tier must not throw at the schema tier.
  #
  # A bare string was the original defect at both. Unchecked, it reached
  # children.nix's aspect walk and crashed with a raw Nix `expected a set but
  # found a string` from propagateScope's `//` on the includes side, and on the
  # excludes side `identity.key` reduced it to "<anon>", which matches no
  # policy and so excluded nothing in silence.
  #
  # Recurses into nested lists because `providerType` names a list of policy
  # records as a valid element and children.nix walks nested lists the same way
  # at both tiers (`processInclude`, and `lib.flatten` over excludes since
  # 6127cbc). Admits a function because a parametric aspect reference is one.
  checkCollectionElement =
    collection:
    let
      check =
        v:
        if builtins.isList v then
          map check v
        else if builtins.isAttrs v || lib.isFunction v then
          v
        else
          throw "den: den.schema.<kind>.${collection}: expected a policy or aspect reference, got ${
            if builtins.isString v then ''"${v}"'' else builtins.typeOf v
          }";
    in
    check;

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
  options.den.users = types.usersOption;
  options.den.schema = schemaLib.mkSchemaOption {
    collections = {
      # includes / excludes are policy over aspects, not the kind's shape: their
      # elements may reach back into the instances the kind types (#719), so
      # gen-schema must not read them into the kind's identity.
      includes = {
        default = [ ];
        merge = acc: val: acc ++ map (checkCollectionElement "includes") val;
        identity = false;
      };
      excludes = {
        default = [ ];
        merge = acc: val: acc ++ map (checkCollectionElement "excludes") val;
        identity = false;
      };
      # What a receiver of this kind admits (#694 §12). Set values only: a
      # layer that leaves `default` unset doesn't loosen a "deny".
      admits = {
        default = {
          default = null;
          allow = [ ];
          deny = [ ];
        };
        merge = acc: val: {
          default =
            if acc.default == "deny" || (val.default or null) == "deny" then
              "deny"
            else
              val.default or acc.default;
          allow = acc.allow ++ (val.allow or [ ]);
          deny = acc.deny ++ (val.deny or [ ]);
        };
        identity = false;
      };
      # Who may exclude the policies registered by this kind (#694 §11a O2):
      # the strictest value any layer sets wins.
      policyEnforcement = {
        default = null;
        merge =
          acc: val:
          (import ./../nix/lib/enforcement.nix { inherit lib; }).strictest [
            acc
            val
          ];
        identity = false;
      };
      # How a declared user field combines the registry user with a host's
      # `user@host` override when both set it in the same priority band:
      # `den.lib.fold.replace` (the default) or `den.lib.fold.append`.
      folds = {
        default = { };
        merge =
          acc: val:
          acc
          // builtins.mapAttrs (
            f: v:
            if
              !(builtins.elem v [
                "replace"
                "append"
              ])
            then
              throw "den: den.schema.<kind>.folds.${f}: `${toString v}` isn't a fold; use den.lib.fold.replace or den.lib.fold.append."
            else if acc ? ${f} && acc.${f} != v then
              throw "den: den.schema.<kind>.folds.${f} is declared both `${acc.${f}}` and `${v}`; a field folds one way."
            else
              v
          ) val;
        identity = false;
      };
      isEntity = {
        default = false;
        merge = acc: val: acc || val;
      };
      isolated = {
        default = false;
        merge = acc: val: acc || val;
      };
      # Selects the kind's closed instance type (gen-schema's strict freeform)
      # instead of the open one; see `den.lib.strict`.
      isStrict = {
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
              "admits"
              "policyEnforcement"
              "folds"
              "isEntity"
              "isolated"
              "isStrict"
              "parent"
              "collisionPolicy"
            ];
            stripped = if builtins.isAttrs v then builtins.removeAttrs v collectionKeys else v;
          in
          !builtins.isAttrs stripped || stripped != { }
        ) defs;
      # `imports = [ den.lib.strict ]` is the spelling from when it was a module.
      isStrict =
        collections.isStrict
        || builtins.any (
          d:
          builtins.isAttrs d.value
          && builtins.elem strictEntry (d.value.imports or [ ])
          && lib.warn ''
            den: `imports = [ den.lib.strict ]` on a schema entry is deprecated (in ${d.file or "an unknown file"}).
            den.lib.strict is now a schema entry, not a module. Migrate:
              - den.schema.<kind>.imports = [ den.lib.strict ];
              + den.schema.<kind>.isStrict = true;   # or: den.schema.<kind> = den.lib.strict;
          '' true
        ) defs;
    };
  };
  # Built-in entity topology: users nest inside hosts, homes nest inside hosts.
  config.den.schema.user.parent = "host";
  config.den.schema.home.parent = "host";

  options.den.migrations.user-host-content.acknowledged = lib.mkOption {
    description = ''
      Adopt #694's end state now. Until ${removalDate}, den keeps two
      transition defaults on every host, the `user-aspects` and
      `mutual-provider` batteries, so content a user-placed aspect writes to
      its host's class still reaches the host, with a warning. Setting this
      turns both defaults off: that content stays with the user, and only
      batteries included explicitly apply.
    '';
    type = lib.types.bool;
    default = false;
  };

  # Internal: the flake's resolve, shared by the flake outputs built from it and
  # the fleet landing index that class-module hasAspect reads.
  options.den.__fleet = lib.mkOption {
    internal = true;
    visible = false;
    readOnly = true;
    type = lib.types.raw;
    default = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
  };

  # Private prototype, its public name pending: the finalized landing query.
  # `den.lib.__hasLandedAspect
  # { entity; within ? { }; } ref` is true when ref's content, or that of an
  # aspect it includes, lands in the entity's own evaluation in its primary
  # class (`.forClass c ref` for another class). `within` names the bindings
  # above a non-root entity (`{ inherit host; }` for a user). Reads what the
  # fleet builds, so call it from class modules or after the walk, never from
  # a policy or an includes list.
  config.den.lib.__landingOf =
    sctx: e:
    let
      landing = den.__fleet.fleet.landing;
      direct = landing.${e.id_hash or ""} or null;
      owners =
        builtins.filter
          (
            o:
            builtins.isAttrs o
            && o ? id_hash
            && ((landing.${o.id_hash} or { }).below or { }) ? ${e.id_hash or ""}
          )
          (
            map (k: sctx.${k}) (
              builtins.filter (k: builtins.elem k (den.schema._kindNames or [ ])) (builtins.attrNames sctx)
            )
          );
    in
    if direct != null then
      direct
    else if owners != [ ] then
      landing.${(lib.head owners).id_hash}.below.${e.id_hash}
    else
      null;
  config.den.lib.__hasLandedAspect =
    {
      entity,
      within ? { },
    }:
    let
      landing = den.lib.__landingOf within entity;
    in
    if landing == null then
      throw "den: __hasLandedAspect: `${entity.name or "?"}` is not an entity the flake instantiates, nor one below such an entity named in `within`"
    else
      den.lib.aspects.__mkLateHasAspect {
        inherit landing;
        inherit (den.__fleet.fleet) chains;
        classes = entity.classes or (lib.optional (entity ? class) entity.class);
      };

  # Internal: den's own test suite runs without the transition defaults, so it
  # tests the end state; one dedicated file re-enables them.
  options.den.internal.transitionDefaults = lib.mkOption {
    internal = true;
    visible = false;
    type = lib.types.bool;
    default = true;
  };

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
  # An instance's own `includes` / `excludes` are read by `resolveEntity` for
  # every kind, so `conf` declares them for every kind that inherits it. Left
  # undeclared, only the open instance type accepted them and a strict kind
  # refused den's own instance-level key. `listOf raw` is not a primitive type,
  # so gen-schema keeps both out of the instance identity.
  config.den.schema.conf.imports = [
    {
      options.includes = lib.mkOption {
        description = "Aspects and policies included for this instance only.";
        type = lib.types.listOf lib.types.raw;
        default = [ ];
      };
      options.excludes = lib.mkOption {
        description = "Aspects and policies excluded from this instance's subtree.";
        type = lib.types.listOf lib.types.raw;
        default = [ ];
      };
    }
  ];
  config.den.schema.fleet = { };
  config.den.schema.host.inherits = [ den.schema.conf ];
  config.den.schema.user.inherits = [ den.schema.conf ];
  # A per-host `includes` adds to the registry user's rather than dropping it.
  config.den.schema.user.folds = {
    includes = "append";
    excludes = "append";
  };
  # `home` keys its identity on the registry key plus the system. `name` IS the
  # registry key and gen-schema injects it as an identity key by construction,
  # so only `system` needs declaring — and it has to be declared HERE because
  # gen-schema closes the identity-key set the moment the kind is a value, and
  # an option contributed through `mkInstanceType`'s `extraModules` arrives
  # after that. Naming an undeclared key from `_identity.keys` is a hard error.
  #
  # Declared here, defined on the instance: identity reflects declarations, so
  # the per-system value stays where it is computed.
  #
  # `visible = false`, never `internal = true`: gen-schema's `isPrimitiveOption`
  # drops an `internal` option from the identity set outright, so marking this
  # internal would un-declare the very key `_identity.keys` names. It reads
  # `internal` and `identity` and NOT `visible`, so this hides the key from
  # rendered option docs while leaving it identity-eligible. That rests on
  # `visible` not being read, which is an implementation fact rather than a
  # documented contract — if gen-schema ever folds `visible` into the same
  # presentation exclusion, this key silently leaves the identity set.
  config.den.schema.home.inherits = [ den.schema.conf ];
  config.den.schema.home.imports = [
    {
      options.system = lib.mkOption {
        type = lib.types.str;
        visible = false;
        description = "platform system";
      };
    }
  ];
  config.den.classes = {
    nixos.description = "NixOS system configuration";
    darwin.description = "nix-darwin system configuration";
  };
}
