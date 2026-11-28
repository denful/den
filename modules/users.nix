# User-side assignment (#781): `den.users.<n>.hosts`, read by the builtin
# `den.policies.user-to-hosts`, plus the fleet-level hostless diagnostic.
{
  lib,
  config,
  options,
  ...
}:
let
  inherit (config) den;
  inherit (den.lib) cond;

  suppressLambdaWarnings = den.migrations.anonymous-predicates.suppressWarnings;

  # Declared host names by system, read without evaluating any host.
  hostSystems = builtins.mapAttrs (_: builtins.attrNames) den.hosts;
  systemsOf =
    name: builtins.filter (s: builtins.elem name hostSystems.${s}) (builtins.attrNames hostSystems);

  # One warning per user that writes a function entry, however many hosts read
  # it: forced once per evaluation.
  warnOrThrow = if den.internal.warningsAsErrors then msg: _: throw msg else lib.warn;
  lambdaWarned = builtins.mapAttrs (
    n: _:
    warnOrThrow ''
      den: den.users.${n}.hosts has an inline function. Use a condition (`den.lib.cond.eq [ "host" "<fact>" ] <value>`) or a named predicate (`den.lib.cond.predicate "<name>"` with `den.predicates.<name>`) instead (https://den.denful.dev/guides/users/#from-inline-functions-in-hosts); set `den.migrations.anonymous-predicates.suppressWarnings = true` to silence this.
    '' true
  ) den.users;

  # The condition context: each side's facts plus its identity, as the paths
  # `[ "host" "<fact>" … ]` and `[ "user" "<fact>" … ]` read them.
  condContext = host: user: {
    host = host.facts // {
      inherit (host) name system class;
    };
    user = user.facts // {
      inherit (user) name userName;
    };
  };

  checkPaths =
    n: ctx: t:
    map (
      p:
      if builtins.length p < 2 || !(ctx ? ${builtins.head p}) then
        throw "den: den.users.${n}.hosts reads `${lib.concatStringsSep "." p}`; a condition reads `host.<fact>` or `user.<fact>`."
      else if !(ctx.${builtins.head p} ? ${builtins.elemAt p 1}) then
        throw "den: den.users.${n}.hosts reads `${lib.concatStringsSep "." p}`, but no `${builtins.elemAt p 1}` fact is declared for ${builtins.head p}s (den.schema.${builtins.head p}.facts) and it isn't one of ${builtins.head p}'s identity fields."
      else
        true
    ) (cond.paths t);

  # Whether entry `e` of user `n`'s `hosts` assigns `n` to `host`. Every entry
  # is checked, so a bad entry fails even when another one matches.
  entryMatches =
    n: host: user: e:
    if builtins.isString e then
      let
        systems = systemsOf e;
      in
      if systems == [ ] then
        throw "den: den.users.${n}.hosts names host '${e}', but no host by that name is declared."
      else if builtins.length systems > 1 then
        throw "den: den.users.${n}.hosts names host '${e}', which is declared on ${
          lib.concatMapStringsSep ", " (s: "${s}.${e}") systems
        }; use a condition on `host.name` and `host.system` to pick one."
      else
        e == host.name && builtins.head systems == host.system
    else if cond.isPredicate e then
      let
        name = e.__denPredicate;
        p =
          den.predicates.${name}
            or (throw "den: den.users.${n}.hosts uses predicate '${name}', but den.predicates has no such predicate.");
        r = p { inherit host user; };
      in
      if builtins.isBool r then
        r
      else
        throw "den: den.predicates.${name} returned a ${builtins.typeOf r} for user '${n}', not a bool."
    else if cond.isRefusal e then
      throw "den: an entry of den.users.${n}.hosts is a condition den can't decide (${e.left.code}): ${
        builtins.toJSON (e.left.witness or { })
      }"
    else if cond.isCondition e then
      let
        ctx = condContext host user;
      in
      builtins.deepSeq (checkPaths n ctx e) (cond.decide "an entry of den.users.${n}.hosts" ctx e)
    else if builtins.isFunction e then
      let
        r = e { inherit host user; };
      in
      if !(builtins.isBool r) then
        throw "den: a function in den.users.${n}.hosts returned a ${builtins.typeOf r}, not a bool."
      else if suppressLambdaWarnings then
        r
      else
        builtins.seq lambdaWarned.${n} r
    else
      throw "den: den.users.${n}.hosts has a ${builtins.typeOf e}; an entry is a host name, a `den.lib.cond` condition, `den.lib.cond.predicate \"<name>\"` or a function.";

  assigns =
    host: user: n:
    let
      entries = den.users.${n}.hosts;
      results = map (entryMatches n host user) entries;
    in
    entries != null && builtins.deepSeq results (builtins.elem true results);

  # Users a fleet would leave on no host: `hosts` unset, no host has them and
  # no standalone home names them. Only while user-to-hosts runs somewhere,
  # since configs assigning entirely through their own policies opt out of it.
  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);
  allHomes = lib.concatMap builtins.attrValues (builtins.attrValues den.homes);
  userToHostsActive = builtins.any (h: builtins.elem "user-to-hosts" h.__assignmentPolicies) allHosts;
  hostless = lib.optionals userToHostsActive (
    builtins.filter (
      n:
      den.users.${n}.hosts == null
      && !(builtins.any (h: h.users ? ${n}) allHosts)
      && !(builtins.any (home: home.userName == n) allHomes)
    ) (builtins.attrNames den.users)
  );

  hasChecks = ((options.flake.type.getSubOptions or (_: options.flake)) { }) ? checks;
in
{
  options.den.predicates = lib.mkOption {
    description = ''
      Named predicates for `den.users.<n>.hosts` entries
      (`den.lib.cond.predicate "<name>"`): `{ host, user, ... }: <bool>`, where
      `host` is `{ name; system; class; facts; }` and `user` is
      `{ name; userName; facts; }`. A predicate should read only those.
    '';
    type = lib.types.attrsOf (lib.types.uniq lib.types.raw);
    default = { };
  };

  options.den.migrations.anonymous-predicates.suppressWarnings = lib.mkOption {
    description = "Silence the warning for an inline function in `den.users.<n>.hosts`. Never silences an error.";
    type = lib.types.bool;
    default = false;
  };

  options.den.migrations.resolution-assignments.suppressWarnings = lib.mkOption {
    description = ''
      Silence the warning for a host policy that assigns users during
      resolution (`resolve.to "user"`). `den.users` with
      `den.lib.policy.assign` or `den.users.<n>.hosts` is the source of truth
      for host assignment. Never silences an error.
    '';
    type = lib.types.bool;
    default = false;
  };

  # den's own suite turns its migration warnings into errors, so a cell can
  # assert that a config warns, or that it doesn't.
  options.den.internal.warningsAsErrors = lib.mkOption {
    internal = true;
    visible = false;
    type = lib.types.bool;
    default = false;
  };

  options.den.internal.hostlessUsers = lib.mkOption {
    description = "Registry users the fleet assigns to no host and no home binds.";
    internal = true;
    visible = false;
    readOnly = true;
    type = lib.types.raw;
    default = hostless;
  };

  config = {
    den.policies.user-to-hosts = den.lib.policy.assign (
      { host, users }:
      # Each user's own view, so a predicate sees `hosts`' owner as `user`.
      builtins.filter (n: assigns host users.${n} n) (builtins.attrNames users)
    );
    den.schema.host.includes = [ den.policies.user-to-hosts ];

    # Fleet-level: needs every host's assignments, so only the flake checks
    # read it; building one host never does.
    flake = lib.optionalAttrs hasChecks {
      checks = lib.mkIf (hostless != [ ]) (
        lib.warn ''
          den: ${lib.concatMapStringsSep ", " (n: "den.users.${n}") hostless} ${
            if builtins.length hostless == 1 then "is" else "are"
          } on no host and no standalone home. Assign ${
            if builtins.length hostless == 1 then "it" else "them"
          } (`hosts`, `den.hosts.<s>.<h>.users.<n>` or an assignment policy), give ${
            if builtins.length hostless == 1 then "it" else "them"
          } a home, or set `hosts = [ ];` to mark ${
            if builtins.length hostless == 1 then "it" else "them"
          } hostless on purpose.
        '' { }
      );
    };
  };
}
