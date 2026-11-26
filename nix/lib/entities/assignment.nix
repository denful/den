# The assignment stage: which users are on which host, decided before any
# host is resolved and over declared data only (facts and identities), so
# resolution reads the result and never decides it.
{ lib, den, ... }:
let
  # A kind's facts, evaluated on their own: a fact sees other facts and the
  # entity's identity, never the entity, its users or the rest of the config,
  # so assignment can't depend on its own result.
  evalFacts =
    kind: identity: raw:
    let
      refuse =
        arg:
        throw "den: a fact of ${kind} '${identity.name}' reads `${arg}`. Facts are evaluated on their own, before ${kind}s are assigned, so a fact can read other facts (`config`) and `name`${
          lib.optionalString (kind == "host") ", `system`, `class`"
        } only.";
    in
    (lib.evalModules {
      modules = (den.schema.${kind}.facts or [ ]) ++ [
        {
          config = raw;
          _file = "<den.${kind}s.${identity.name}.facts>";
        }
        {
          config._module.args = {
            host = refuse "host";
            user = refuse "user";
            users = refuse "users";
            home = refuse "home";
          }
          // identity;
        }
      ];
    }).config;

  # Stage-0 assignment functions travel on an ordinary policy record, so they
  # share den.policies and the includes/excludes spelling. Resolution calls the
  # record's `fn` like any host policy; it emits nothing, and refuses to run
  # where the stage never selected it (den.default), which would otherwise be
  # silently inert.
  assignKey = "__assignUsers";
  unnamed = "<assign>";
  resolutionFn =
    name:
    { host, ... }:
    if builtins.elem name (host.__assignmentPolicies or [ ]) then
      [ ]
    else
      throw "den: assignment policy `${name}` reached resolution for host '${host.name}' without the assignment stage selecting it, so it assigned no one. Assignment runs before resolution and reads only `den.schema.host.includes` and a host's own `includes`; move it there (not `den.default.includes`).";
  mkAssign = f: {
    __isPolicy = true;
    name = unnamed;
    ${assignKey} = f;
    fn = resolutionFn unnamed;
    # policy-type.nix rebuilds `fn` from this once `den.policies` names it.
    __namedFn = resolutionFn;
  };
  isAssign = p: builtins.isAttrs p && p ? ${assignKey};

  flat = l: lib.flatten l;

  includedOf =
    rawHost:
    builtins.filter isAssign (flat ((den.schema.host.includes or [ ]) ++ (rawHost.includes or [ ])));

  # An entry that discharges to nothing (a false `mkIf`, nested or not, or an
  # empty `mkMerge`) declares no user: the module system's own rule, so every
  # reader of the declared names drops it as `users` does.
  # The module system's rule, inlined: lib.modules.dischargeProperties warns on external use.
  discharge =
    v:
    if v._type or null == "merge" then
      lib.concatMap discharge v.contents
    else if v._type or null == "if" then
      if v.condition then discharge v.content else [ ]
    else
      [ v ];
  isDisabled = v: builtins.isAttrs v && discharge v == [ ];
  declaredOf = rawHost: lib.filterAttrs (_: v: !(isDisabled v)) (rawHost.users or { });

  # `fleetIncluded`: every assignment policy any host includes, so a host may
  # exclude one another host includes.
  selectPolicies =
    fleetIncluded: rawHost:
    let
      included = includedOf rawHost;
      excluded = builtins.filter isAssign (
        flat ((den.schema.host.excludes or [ ]) ++ (rawHost.excludes or [ ]))
      );
      anonymous = builtins.filter (p: p.name == unnamed) (included ++ excluded);
      excludedNames = map (p: p.name) excluded;
      unknown = lib.subtractLists (map (p: p.name) fleetIncluded) excludedNames;
    in
    if anonymous != [ ] then
      throw "den: an assignment policy is used without a name. Register it as `den.policies.<name> = den.lib.policy.assign …` and include `den.policies.<name>`."
    else if unknown != [ ] then
      throw "den: assignment polic${if builtins.length unknown == 1 then "y" else "ies"} ${
        lib.concatMapStringsSep ", " (n: "`${n}`") unknown
      } excluded, but not included for any host; check the name."
    else
      lib.unique (builtins.filter (p: !(builtins.elem p.name excludedNames)) included);

  hostIdentity = system: name: rawHost: {
    inherit name system;
    class = rawHost.class or (if lib.hasSuffix "darwin" system then "darwin" else "nixos");
  };

  # What an assignment policy sees of each registry user.
  usersView = builtins.mapAttrs (name: u: {
    inherit name;
    inherit (u) userName facts;
  }) den.users;

  # The declared hosts with every stage-0 assignment added to `users`, and
  # `__assignments` recording, per user, every source that assigned it.
  assign =
    normalized:
    let
      fleetIncluded = lib.concatMap (system: lib.concatMap includedOf (builtins.attrValues system)) (
        builtins.attrValues normalized
      );
    in
    builtins.mapAttrs (
      system:
      builtins.mapAttrs (
        name: rawHost:
        let
          identity = hostIdentity system name rawHost;
          hostView = identity // {
            facts = evalFacts "host" identity (rawHost.facts or { });
          };
          declared = builtins.attrNames (declaredOf rawHost);
          # Each selected policy's function is called once per host.
          fromPolicy =
            p:
            let
              names = p.${assignKey} {
                host = hostView;
                users = usersView;
              };
              bad = builtins.filter (n: !(builtins.isString n) || !(den.users ? ${n})) names;
            in
            if !(builtins.isList names) then
              throw "den: assignment policy `${p.name}` returned a ${builtins.typeOf names} for host '${name}'; it returns a list of user names."
            else if bad != [ ] then
              throw "den: assignment policy `${p.name}` assigned ${
                lib.concatMapStringsSep ", " (n: if builtins.isString n then "'${n}'" else builtins.typeOf n) bad
              } to host '${name}', but den.users has no such user."
            else
              map (n: {
                user = n;
                source = "policy:${p.name}";
              }) names;
          assigned =
            map (n: {
              user = n;
              source = "host.users";
            }) declared
            ++ lib.concatMap fromPolicy (selectPolicies fleetIncluded rawHost);
          bySource = builtins.groupBy (a: a.user) assigned;
        in
        rawHost
        // {
          users =
            (rawHost.users or { })
            // lib.genAttrs (lib.subtractLists declared (builtins.attrNames bySource)) (_: { });
          __assignments = builtins.mapAttrs (_: as: lib.unique (map (a: a.source) as)) bySource;
          __assignmentPolicies = map (p: p.name) (selectPolicies fleetIncluded rawHost);
          __declaredUsers = declaredOf rawHost;
        }
      )
    ) normalized;
in
{
  inherit
    evalFacts
    mkAssign
    isAssign
    assign
    ;
}
