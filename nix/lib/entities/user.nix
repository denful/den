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

  # One position's evaluation, kept beside what the composer reads of it:
  # `config` and `provenance` from one evaluation of the paired instance; its
  # own fields (a plain entry's keys, else the fields it defines beyond the
  # schema's own); and `shared`, the schema's contribution alone, the same
  # instance evaluated with no definitions, which every position carries and
  # an `append` counts once.
  mkLayer =
    pair: loc: defs:
    let
      r = pair.evaluate loc defs;
      shared = pair.evaluate loc [ ];
      plain = builtins.all (d: isPlainEntry d.value) defs;
      defCount =
        p:
        if !(builtins.isAttrs p) then
          0
        else if p ? defs && (builtins.isList p.defs) then
          builtins.length p.defs
        else
          lib.foldl' (n: c: n + defCount c) 0 (builtins.attrValues p);
    in
    r
    // {
      inherit shared;
      # `facts` and `hosts` are no composed fields, but a host position
      # defining one is refused.
      sets =
        f:
        if plain then
          builtins.any (d: builtins.elem f (ownKeys d.value)) defs
        else
          defCount (r.provenance.${f} or null) > defCount (shared.provenance.${f} or null);
      # A plain entry's keys that its own evaluation kept: a key under a false
      # `mkIf` names no field.
      own =
        if plain then
          builtins.filter (f: r.config ? ${f}) (lib.unique (lib.concatMap (d: ownKeys d.value) defs))
        else
          builtins.filter (
            f:
            !(builtins.elem f unfolded)
            && defCount r.provenance.${f} > defCount (shared.provenance.${f} or null)
          ) (builtins.attrNames r.provenance);
    };

  # A field's effective priority, from its provenance: a declared option's
  # selected priority (the strongest over its nested options), or a freeform
  # key's where gen observes the key's own selection. A freeform key gen can't
  # observe competes as `set`.
  prioOf =
    p:
    let
      leaves =
        q:
        if !(builtins.isAttrs q) then
          [ ]
        else if q ? defs && builtins.isList q.defs then
          [ q ]
        else
          lib.concatMap leaves (builtins.attrValues q);
      prios = builtins.filter builtins.isInt (
        map (r: if r.priorityState or "observed" == "observed" then r.priority else null) (leaves p)
      );
    in
    if prios == [ ] then
      lib.modules.defaultOverridePriority
    else
      lib.foldl' lib.min (lib.head prios) prios;

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

  # One construction for every registry user, beside its evaluator.
  registryPair = schemaLib.__mkInstancePaired {
    strict = den.schema.user.isStrict;
    extraModules = [
      userFieldsModule
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
      in
      builtins.mapAttrs (
        n: v:
        let
          layer =
            mkLayer registryPair
              [
                "den"
                "users"
                n
              ]
              [
                {
                  file = registryFile;
                  value = v;
                }
              ];
        in
        layer.config // { __layer = layer; }
      ) normalized;
  };

  bandRank = {
    force = 0;
    set = 1;
    default = 2;
  };

  # The host's view of a user: per field, each position's own merge runs first,
  # the stronger priority band wins, and within one band the relation (more
  # specific) wins — or, for an `append` field, the registry's value then the
  # relation's, the schema's shared contribution counted once.
  compose =
    regLayer: relLayer:
    let
      inherit (schemaLib.gen) merge algebra;
      folds = den.schema.user.folds or { };
      rel = relLayer.config;
      live =
        layer: f:
        if !(builtins.elem f layer.own) then
          null
        else
          let
            band = merge.priorityBand (prioOf (layer.provenance.${f} or null));
          in
          if band == "unset" then
            null
          else
            {
              inherit band;
              value = layer.config.${f};
            };
      # `xs` without one occurrence of each of `ys`'s elements, in order.
      withoutOnce =
        xs: ys:
        (lib.foldl'
          (
            acc: x:
            let
              i = lib.lists.findFirstIndex (y: y == x) null acc.left;
            in
            if i == null then
              acc // { kept = acc.kept ++ [ x ]; }
            else
              acc // { left = lib.sublist 0 i acc.left ++ lib.drop (i + 1) acc.left; }
          )
          {
            kept = [ ];
            left = ys;
          }
          xs
        ).kept;
      field =
        f:
        let
          r = live regLayer f;
          l = live relLayer f;
          strategy = folds.${f} or "replace";
          checkList =
            v:
            if strategy == "append" && !builtins.isList v then
              throw "den: user field `${f}` folds by append, which needs a list, but a ${builtins.typeOf v} was defined."
            else
              v;
          # The schema's shared contribution is in the relation's value only
          # where it survived the relation's own band (a relation `mkForce`
          # drops it), and only then is it taken out once.
          sharedSurvived =
            (relLayer.shared.provenance ? ${f})
            && prioOf relLayer.shared.provenance.${f} == prioOf relLayer.provenance.${f};
          relOwn =
            if strategy == "append" then
              withoutOnce (checkList l.value) (lib.optionals sharedSurvived (relLayer.shared.config.${f} or [ ]))
            else
              l.value;
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
              { ${f} = relOwn; }
            ];
            layerNames = [
              "registry"
              "relation"
            ];
          }).value.${f};
      fields = lib.subtractLists unfolded (lib.unique (regLayer.own ++ relLayer.own));
    in
    if relLayer.sets "facts" then
      throw "den: user '${rel.name}' sets `facts` on host '${rel.host.name}'. A user's facts are read before assignment, so they live on `den.users.${rel.name}.facts`, not on a host."
    else if relLayer.sets "hosts" then
      throw "den: user '${rel.name}' sets `hosts` on host '${rel.host.name}'. Which hosts a user is on is the user's, so it lives on `den.users.${rel.name}.hosts`."
    else
      rel // lib.genAttrs fields field // { inherit (regLayer.config) facts hosts; };
in
{
  inherit
    usersOption
    mkLayer
    userFieldsModule
    ownKeys
    isPlainEntry
    rawListValues
    compose
    relationFile
    ;
}
