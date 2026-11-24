# The user registry (`den.users`) and the view a host gets of one of its users:
# the registry user plus the `user@host` relation, combined field by field.
{
  config,
  lib,
  den,
  ...
}:
let
  inherit (import ./_types.nix { inherit lib den; })
    strOpt
    lookupAspect
    deepMergeAttrs
    ;

  schemaLib = den.lib.schema;

  registryFile = "<den.users>";
  relationFile = "<den.hosts>";

  # Fields that describe the entity's identity or wiring rather than the user,
  # so each position keeps its own.
  unfolded = [
    "_module"
    "__layer"
    "name"
    "aspect"
    "host"
    "resolved"
    "__scopeName"
    "collisionPolicy"
    "id_hash"
    "_identity"
    "isStrict"
    "__ownFields"
    "__ownDeclared"
    "__ownPlain"
    "__assignedBy"
    "facts"
    "hosts"
  ];

  # The field names a raw entry sets, seen through the module system's
  # property wrappers so `mkIf`/`mkMerge`/`mkOverride` around a whole entry
  # still name the fields inside it.
  ownKeys =
    v:
    if !builtins.isAttrs v then
      [ ]
    else if v._type or null == "merge" then
      lib.unique (lib.concatMap ownKeys v.contents)
    else if
      builtins.elem (v._type or null) [
        "if"
        "override"
        "order"
      ]
    then
      ownKeys v.content
    else
      builtins.attrNames v;

  # Every list a raw definition of `field` could contribute, through the
  # module system's property wrappers; for stubs, where a superset is harmless.
  rawListValues =
    field: v:
    let
      go =
        x:
        if builtins.isList x then
          x
        else if !builtins.isAttrs x then
          [ ]
        else if x._type or null == "merge" then
          lib.concatMap go x.contents
        else if
          builtins.elem (x._type or null) [
            "if"
            "override"
            "order"
          ]
        then
          go x.content
        else
          [ ];
      field' =
        x:
        if !builtins.isAttrs x then
          [ ]
        else if x._type or null == "merge" then
          lib.concatMap field' x.contents
        else if
          builtins.elem (x._type or null) [
            "if"
            "override"
            "order"
          ]
        then
          field' x.content
        else
          go (x.${field} or [ ]);
    in
    field' v;

  # An entry readable as data. Like nixpkgs' submodule
  # (`shorthandOnlyDefinesConfig`), an attrset entry only defines config, its
  # `imports` included; only a function entry is a module.
  isPlainEntry =
    v:
    builtins.isAttrs v
    && (
      v._type or null == null
      || (
        builtins.elem v._type [
          "if"
          "override"
          "order"
        ]
        && isPlainEntry v.content
      )
      || (v._type == "merge" && builtins.all isPlainEntry v.contents)
    );

  # Read lazily, one field at a time, so composing never forces a field this
  # layer doesn't set — a schema module reading `host` stays unevaluated on a
  # registry entry, which has none.
  layerModule =
    layerFile:
    { options, config, ... }:
    {
      # The declared fields this position defines itself, read from where each
      # definition came from: for a function- or module-shaped entry, whose
      # keys can't be read as data. Forces each option's definitions, defaults
      # included, so plain entries keep reading their keys instead.
      options.__ownDeclared = lib.mkOption {
        internal = true;
        visible = false;
        readOnly = true;
        type = lib.types.raw;
        default = builtins.filter (
          f:
          !(builtins.elem f unfolded)
          && lib.isOption options.${f}
          # den's computed fields (hasAspect, id_hash, …) are not the user's
          # and reading their definitions can resolve the entity.
          && !(options.${f}.internal or false)
          && !(options.${f}.readOnly or false)
          && builtins.any (d: d.file == layerFile) options.${f}.definitionsWithLocations
        ) (builtins.attrNames options);
      };
      options.__layer = lib.mkOption {
        internal = true;
        visible = false;
        readOnly = true;
        type = lib.types.raw;
        default =
          f:
          let
            opt = options.${f};
          in
          if options ? ${f} && lib.isOption opt then
            {
              prio = opt.highestPrio;
              value = config.${f};
              ownValue = opt.type.merge opt.loc (
                builtins.filter (d: d.file == layerFile) opt.definitionsWithLocations
              );
            }
          else
            # shortcut: band precedence covers declared options only; a freeform
            # field has no per-key priority after gen-merge's merge, so it competes
            # as `set`. Read gen-merge's per-key priority once it publishes one.
            {
              prio = lib.modules.defaultOverridePriority;
              value = config.${f};
              ownValue = config.${f};
            };
      };
    };

  # Fields every user position declares. `aspect` differs by position, so each
  # position adds its own.
  userFieldsModule =
    { config, ... }:
    {
      options = {
        userName = strOpt "user account name" config.name;
        classes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "home management nix classes";
          defaultText = lib.literalExpression ''[ "user" ]'';
          default = [ "user" ];
        };
      };
    };

  registryUserType = schemaLib.mkInstanceType {
    strict = den.schema.user.isStrict;
    extraModules = [
      userFieldsModule
      (layerModule registryFile)
      (
        { config, ... }:
        {
          # A registry user is on no host; host-reading schema modules see null.
          config._module.args.host = null;
          options.aspect = lib.mkOption {
            description = "Aspect that configures this user.";
            type = lib.types.raw; # no merging
            defaultText = "den.aspects.<name>";
            default = lookupAspect den config;
          };
          options.hosts = lib.mkOption {
            description = ''
              Hosts this user is assigned to, read by `den.policies.user-to-hosts`:
              declared host names, `den.lib.cond` conditions over facts, named
              predicates (`den.lib.cond.predicate "<name>"`), or (warned) inline
              functions. `null` assigns nothing from here; `[ ]` marks the user
              hostless on purpose.
            '';
            type = lib.types.nullOr (lib.types.listOf lib.types.raw);
            default = null;
          };
          options.facts = lib.mkOption {
            description = "Facts the assignment stage reads; declared under `den.schema.user.facts`.";
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
            apply =
              raw:
              (import ./assignment.nix { inherit lib den; }).evalFacts "user" {
                inherit (config) name userName;
              } raw;
          };
        }
      )
    ]
    ++ schemaLib.strictCompatModules den.schema.user.isStrict;
  } den.schema.user;

  innerType = lib.types.attrsOf registryUserType;

  # Every name a host declares is a registry user, with defaults when
  # `den.users` doesn't declare it. Read from the names declared before
  # assignment: the hosts' `users` come from assignment, which reads den.users.
  hostUserNames = lib.unique (
    lib.concatMap (
      system: lib.concatMap (h: builtins.attrNames h.__declaredUsers) (builtins.attrValues system)
    ) (builtins.attrValues config.den.hosts)
  );

  usersOption = lib.mkOption {
    description = "den user registry: one entry per user, whichever hosts or homes they're on.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.attrsOf (lib.types.submodule { freeformType = deepMergeAttrs; });
    # Normalised to one definition, as `den.hosts` is, so a field's own
    # definitions are told apart from the schema's by file.
    apply =
      raw:
      let
        normalized = lib.genAttrs hostUserNames (_: { }) // raw;
        typed =
          innerType.merge
            [ "den" "users" ]
            [
              {
                file = registryFile;
                value = normalized;
              }
            ];
      in
      builtins.mapAttrs (
        n: u:
        u
        // {
          __ownFields = ownKeys normalized.${n};
          __ownPlain = isPlainEntry normalized.${n};
        }
      ) typed;
  };

  bandRank = {
    force = 0;
    set = 1;
    default = 2;
  };

  # The host's view of `rel`'s user: per declared field, each position's
  # ordinary merge runs first, the stronger priority band wins, and within one
  # band the relation (more specific) wins — or, for an `append` field, the
  # registry's value then the relation's. Freeform fields: see `layerModule`.
  compose =
    relPlain: relRawKeys: reg: rel:
    let
      # A plain entry's own fields are its keys; a module-shaped one's declared
      # fields come from provenance, and its keys add any freeform ones.
      ownOf =
        plain: layer: rawKeys:
        if plain then rawKeys else lib.unique (layer.__ownDeclared ++ rawKeys);
      regOwn = ownOf reg.__ownPlain reg reg.__ownFields;
      relOwn = ownOf relPlain rel relRawKeys;
      inherit (schemaLib.gen) merge algebra;
      folds = den.schema.user.folds or { };
      live =
        layer: owned: f:
        if !(builtins.elem f owned) then
          null
        else
          let
            info = layer f;
            band = merge.priorityBand info.prio;
          in
          if band == "unset" then null else info // { inherit band; };
      field =
        f:
        let
          r = live reg.__layer regOwn f;
          l = live rel.__layer relOwn f;
          strategy = folds.${f} or "replace";
          checkList =
            v:
            if strategy == "append" && !builtins.isList v then
              throw "den: user field `${f}` folds by append, which needs a list, but a ${builtins.typeOf v} was defined."
            else
              v;
        in
        if r == null && l == null then
          rel.${f}
        else if r == null then
          l.value
        else if l == null then
          r.value
        else if bandRank.${r.band} < bandRank.${l.band} then
          r.value
        else if bandRank.${l.band} < bandRank.${r.band} then
          l.value
        else
          (algebra.record.foldLayersTraced {
            strategies.${f} = strategy;
            layers = [
              { ${f} = checkList r.value; }
              { ${f} = checkList (if strategy == "append" then l.ownValue else l.value); }
            ];
            layerNames = [
              "registry"
              "relation"
            ];
          }).value.${f};
      fields = lib.subtractLists unfolded (lib.unique (regOwn ++ relOwn));
    in
    if builtins.elem "facts" relOwn then
      throw "den: user '${rel.name}' sets `facts` on host '${rel.host.name}'. A user's facts are read before assignment, so they live on `den.users.${rel.name}.facts`, not on a host."
    else if builtins.elem "hosts" relOwn then
      throw "den: user '${rel.name}' sets `hosts` on host '${rel.host.name}'. Which hosts a user is on is the user's, so it lives on `den.users.${rel.name}.hosts`."
    else
      rel // lib.genAttrs fields field // { inherit (reg) facts hosts; };
in
{
  inherit
    usersOption
    layerModule
    userFieldsModule
    ownKeys
    isPlainEntry
    rawListValues
    compose
    relationFile
    ;
}
