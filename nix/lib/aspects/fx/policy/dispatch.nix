# Policy dispatch — run policies against a context, return classified results.
{
  lib,
  den,
  resolveArgsSatisfied,
  classifyPolicyResult,
  extractTaggedEffects,
  hasEffects,
}:
let
  validEffectTypes = {
    resolve = true;
    include = true;
    exclude = true;
    route = true;
    instantiate = true;
    provide = true;
    pipe = true;
    spawn = true;
  };

  # Validate that each effect returned by a policy has a valid __policyEffect tag.
  validateEffects =
    policyName: rawEffects:
    lib.imap0 (
      i: eff:
      if !(builtins.isAttrs eff) then
        throw "den: policy '${policyName}' returned invalid effect at index ${toString i}: expected attrset, got ${builtins.typeOf eff}"
      else if !(eff ? __policyEffect) then
        throw "den: policy '${policyName}' returned invalid effect at index ${toString i}: missing __policyEffect — use den.lib.policy.resolve/include/exclude/route/instantiate/provide/pipe"
      else if !(validEffectTypes ? ${eff.__policyEffect}) then
        throw "den: policy '${policyName}' returned unknown effect type '${eff.__policyEffect}' at index ${toString i}"
      else
        eff
    ) rawEffects;

  # An instance firing below its registrant applies to the registrant too
  # (#694 §11a R3): its bare includes land in full where it fired, and their
  # host-class part reaches the registrant through a provenance route (the
  # mutual-provider mechanism, aspect/provide.nix); a provide or route with no
  # receiver is aimed at the registrant. A user the registrant accepts through
  # user-aspects is already unbounded, so the route stands down (R5).
  provenanceMarker = "den-provides-to-host=";
  applyToRegistrant =
    policyName: registrant: ctx: effects:
    let
      firingKind = ctx.__entityKind or null;
      firing = if firingKind == null then null else ctx.${firingKind} or null;
      reg = registrant.record;
      # Where the host-class part lands: the registrant, or for a class-less
      # registrant the nearest classed entity below it (R3 (a), registrant.nix).
      target = if (registrant.classTarget or null) == null then null else registrant.classTarget.record;
      # Firing at the target itself, the content is already where it belongs.
      atTarget = target != null && (firing.id_hash or null) == target.id_hash;
      # Only a firing entity with an identity can be told apart from the
      # registrant; one without (a hand-built record) is treated as the
      # registrant's own scope.
      isBelow =
        firing != null
        && (firing.id_hash or null) != null
        && firing.id_hash != reg.id_hash
        && ((ctx.${registrant.kind} or { }).id_hash or null) == reg.id_hash;
      token = "${reg.id_hash}/${policyName}";
      registrantClasses = lib.optionals (target != null && !atTarget) [
        target.class
        "os"
      ];
      isInclude = e: e.__policyEffect == "include";
      aimed =
        e:
        if
          builtins.elem e.__policyEffect [
            "provide"
            "route"
          ]
          && (e.value.receiver or null) == null
          # appendToParent already names its target.
          && !(e.value.appendToParent or false)
          # Only the registrant's own class is its part, as for an include: a
          # route into a user-side class (homeManager) stays where it fired.
          && builtins.elem (e.value.intoClass or e.value.class or null) registrantClasses
        then
          e
          // {
            value = e.value // {
              receiver = target;
            };
          }
        else
          e;
      wrapped =
        e:
        e
        // {
          value = {
            name = "${provenanceMarker}${token}";
            includes = [ e.value ];
          };
        };
      hasIncludes = builtins.any isInclude effects;
      accepted = firing != null && den.lib.acceptance.accepts ctx target firing;
      delivery = lib.optional (hasIncludes && target != null && !atTarget && !accepted) (
        den.lib.policy.route {
          fromClass = target.class;
          intoClass = target.class;
          receiver = target;
          __fromProvenance = token;
        }
      );
    in
    if registrant == null || !isBelow then
      effects
    else
      map (e: if isInclude e then wrapped e else aimed e) effects ++ delivery;

  # Dispatch aspect policies against a context.
  # Note: caller passes the same aspectPolicies each iteration; Nix memoizes
  # attrsToList per attrset identity, so repeated calls are cheap.
  dispatchAspect =
    aspectPolicies: firedPolicies: resolveCtx:
    let
      # `self` is always bound to the dispatching scope's context, so a policy
      # can guard with `{ self, ... }:` to mean "fire at my registration scope"
      # — distinct from `{ <kind>, ... }:` which fans across entities of that
      # kind. The binding must be present (not just allowed) because Nix's
      # attrset pattern requires every named arg, used or not. See the
      # late-dispatch filter in policy/schema.nix, which keeps `self`-guarded
      # policies from re-firing at descendant scopes.
      ctx = resolveCtx // {
        self = resolveCtx.self or resolveCtx;
      };
      entries = lib.attrsToList aspectPolicies;
      matching = builtins.filter (
        e: resolveArgsSatisfied e.value.fn ctx && !(firedPolicies ? ${e.name})
      ) entries;
    in
    map (
      entry:
      let
        result = entry.value.fn ctx;
        rawEffects = if builtins.isList result then result else [ result ];
      in
      {
        policyName = entry.name;
        effects = applyToRegistrant entry.name (entry.value.registrant or null) ctx (
          validateEffects entry.name rawEffects
        );
      }
    ) matching;

  # Combined dispatch returning classified + tagged results.
  mkDispatch =
    aspectPolicies: firedPolicies: resolveCtx:
    let
      allResults = dispatchAspect aspectPolicies firedPolicies resolveCtx;
      classified = map classifyPolicyResult allResults;
      tagged = extractTaggedEffects classified;
    in
    tagged
    // {
      enrichment = builtins.foldl' (acc: r: acc // r.mergedEnrichment) { } classified;
      firedNames = map (r: r.policyName) (builtins.filter hasEffects classified);
    };
in
{
  inherit dispatchAspect mkDispatch;
}
