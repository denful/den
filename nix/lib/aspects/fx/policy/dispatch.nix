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

  # Fields only den's own deliveries carry (#694): a provenance token, a
  # stand-down, the transition default's mark. Dropped from the effects of a
  # policy den didn't make, so an author can't set them.
  # `__standDownAspect` and `__transitionDefault` act only beside the other
  # two; they're dropped for completeness.
  denOnlyFields = [
    "__fromProvenance"
    "__standDown"
    "__standDownAspect"
    "__transitionDefault"
  ];
  scrub =
    entry: e:
    if
      (entry.value.denMade or false)
      || !(builtins.elem e.__policyEffect [
        "provide"
        "route"
      ])
    then
      e
    else
      e // { value = builtins.removeAttrs e.value denOnlyFields; };

  # An instance firing below its registrant applies to the registrant too
  # (#694 §11a R3): its bare includes land in full where it fired, and their
  # host-class part reaches the registrant through a provenance route (the
  # mutual-provider mechanism, aspect/provide.nix); a provide or route with no
  # receiver is aimed at the registrant. A user the registrant accepts through
  # user-aspects is already unbounded, so the route stands down (R5).
  provenanceMarker = "den-provides-to-host=";
  inherit (import ./entity-identity.nix { inherit lib; }) sameEntity entityKey;
  applyToRegistrant =
    policyName: registrant: ctx: effects:
    let
      firingKind = ctx.__entityKind or null;
      firing = if firingKind == null then null else ctx.${firingKind} or null;
      reg = registrant.record;
      # Where the host-class part lands: the registrant, or for a class-less
      # registrant the nearest classed entity below it (R3 (a), registrant.nix).
      target = if (registrant.classTarget or null) == null then null else registrant.classTarget.record;
      isEntity =
        kind: record: other:
        firingKind == kind && builtins.isAttrs record && sameEntity kind record other;
      # Firing at the target itself, the content is already where it belongs.
      atTarget = target != null && isEntity registrant.classTarget.kind firing target;
      # Below the registrant: the firing entity is not the registrant, and the
      # scope binds the registrant's kind to it.
      isBelow =
        firing != null
        && !(isEntity registrant.kind firing reg)
        && builtins.isAttrs (ctx.${registrant.kind} or null)
        && sameEntity registrant.kind ctx.${registrant.kind} reg;
      token = "${entityKey registrant.kind reg}/${policyName}";
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
          # Outermost: a provider inside the delivered include stays innermost.
          __denProvenance = [ token ] ++ e.__denProvenance or [ ];
        };
      hasIncludes = builtins.any isInclude effects;
      accepted = firing != null && den.lib.acceptance.acceptsExplicitly ctx target firing;
      # Accepted only through user-aspects' transition default: the bucket
      # reaches the target whole, so the route stands down, recorded for the
      # migration warning (#694).
      acceptedByDefault = !accepted && firing != null && den.lib.acceptance.accepts ctx target firing;
      delivery = lib.optional (hasIncludes && target != null && !atTarget && !accepted) (
        den.lib.policy.route {
          fromClass = target.class;
          intoClass = target.class;
          receiver = target;
          __fromProvenance = token;
          __standDown = acceptedByDefault;
        }
      );
    in
    # The registrant's own part comes back apart from the author's effects,
    # so admits never has to tell them apart by a field an author can set.
    if registrant == null || !isBelow then
      {
        inherit effects;
        registrantPart = [ ];
      }
    else
      {
        effects = map (e: if isInclude e then wrapped e else aimed e) effects;
        registrantPart = delivery;
      };

  # Receiver acceptance (#694 §12, §11a R7). A delivery naming a receiver is
  # checked against what the receiver admits: its kind's schema layer and its
  # own aspect. An entry matches the emitting policy by value (the record it
  # registered from), or an aspect on its origin chain by identity, so a name
  # can't forge an origin. Den's channels always land.
  admitsOf =
    ctx: receiver:
    let
      # The receiver's kind: an id_hash starts with it (`host:…`); a record
      # without one is found among the context's bindings.
      kind =
        if receiver ? id_hash then
          builtins.head (lib.splitString ":" receiver.id_hash)
        else
          lib.findFirst (k: builtins.isAttrs (ctx.${k} or null) && sameEntity k ctx.${k} receiver) null (
            builtins.filter (k: ((den.schema.${k} or { }).isEntity or false)) (builtins.attrNames ctx)
          );
      layers = lib.optional (kind != null) ((den.schema.${kind} or { }).admits or { }) ++ [
        ((receiver.aspect or { }).admits or { })
      ];
    in
    builtins.foldl'
      (acc: l: {
        default =
          if acc.default == "deny" || (l.default or null) == "deny" then "deny" else l.default or acc.default;
        allow = acc.allow ++ (l.allow or [ ]);
        deny = acc.deny ++ (l.deny or [ ]);
      })
      {
        default = null;
        allow = [ ];
        deny = [ ];
      }
      (lib.optionals (kind != null || true) layers);
  originMatches =
    entry: ref:
    if builtins.isAttrs ref && ref.__isPolicy or false then
      (entry.value.ref or null) == ref || builtins.elem ref (entry.value.originPolicies or [ ])
    else
      let
        id = den.lib.aspects.fx.identity.key ref;
        n = builtins.stringLength id;
      in
      builtins.any (
        c:
        c == id
        || (
          builtins.substring 0 n c == id
          && builtins.elem (builtins.substring n 1 c) [
            "/"
            "("
          ]
        )
      ) (entry.value.origin or [ ]);
  # An include's value with every forward it carries checked on its own: one
  # naming a receiver anywhere in the include's static tree (the include
  # itself, a list at any depth, or nested in `includes`), walked as the
  # include walker walks it (aspect/children.nix processInclude). A withheld
  # forward is dropped and its siblings stay. A forward behind a function
  # isn't built until it is walked, so it isn't seen here. Returns
  # `{ keep; value; }`: `keep` is false only when the value was itself one
  # withheld forward.
  pruneForwards =
    ctx: entry:
    let
      # Named aspects are visited once: an include cycle (cya <-> cyb) is a
      # finite tree to the pipeline, and must be one here too.
      go =
        seen: v:
        if builtins.isList v then
          let
            rs = map (go seen) v;
          in
          {
            keep = true;
            changed = builtins.any (r: r.changed || !r.keep) rs;
            value = map (r: r.value) (builtins.filter (r: r.keep) rs);
          }
        else if !(builtins.isAttrs v) then
          unchanged v
        else if (v.meta.__forward.receiver or null) != null then
          if admitsDelivery ctx entry "include" v.meta.__forward.receiver then
            unchanged v
          else
            {
              keep = false;
              changed = true;
              value = v;
            }
        else if builtins.isList (v.includes or null) then
          let
            id = if v ? name then den.lib.aspects.fx.identity.key v else null;
            inner = go (seen // lib.optionalAttrs (id != null) { ${id} = true; }) v.includes;
          in
          if id != null && seen ? ${id} then
            unchanged v
          else if inner.changed then
            {
              keep = true;
              changed = true;
              value = v // {
                includes = inner.value;
              };
            }
          else
            unchanged v
        else
          unchanged v;
      unchanged = v: {
        keep = true;
        changed = false;
        value = v;
      };
    in
    go { };

  admitted =
    ctx: entry: e:
    admitsDelivery ctx entry e.__policyEffect (e.value.receiver or null);

  # One delivery to `receiver`, from a `provide`, a `route` or a forward an
  # include carries: true to land it, false to withhold it (`admits.deny`), or
  # a throw under `admits.default = "deny"`.
  admitsDelivery =
    ctx: entry: effectType: receiver:
    let
      isInclude = effectType == "include";
      a = admitsOf ctx receiver;
      denied = builtins.any (originMatches entry) a.deny;
      allowed = (entry.value.denChannel or false) || builtins.any (originMatches entry) a.allow;
    in
    if
      !(builtins.isAttrs receiver)
      || !(
        isInclude
        || builtins.elem effectType [
          "provide"
          "route"
        ]
      )
    then
      true
    else if denied then
      false
    else if a.default == "deny" && !allowed then
      let
        kind = ctx.__entityKind or null;
        source = if kind == null then null else (ctx.${kind} or { }).name or null;
        # What to add: the battery for its own delivery, else the policy or an
        # aspect it is included through.
        # The name the policy was written with, not its registry key, which
        # a same-named policy displaces to a chain-qualified one.
        # A guard: no policy name carries a store path today, but an
        # import-tree identity does, and readers never show its hash.
        name = den.lib.argsName.withoutStoreHash (entry.value.displayName or entry.name);
        allowHint =
          if (entry.value.originPolicies or [ ]) != [ ] then
            "`den.batteries.${(builtins.head entry.value.originPolicies).name}`"
          else
            "the policy `${name}`, or an aspect it is included through";
      in
      throw "den: delivery of `${name}`${
        lib.optionalString (source != null) " from ${source}"
      } denied on ${receiver.name or "<unnamed>"}: `admits.default = \"deny\"`; to admit it, add ${allowHint} to `admits.allow`"
    else
      true;

  # Den's provenance fields on an effect (#694): the tokens its include is
  # walked under, outermost first, and the registration chain of the policy
  # that emitted it. Only den sets them; whatever an author's effect carries
  # is replaced. A policy registered inside a cross-provider include emits
  # under that provider, as the include's static content is; den's provides
  # policies (aspect/provide.nix) set their own.
  denProvenance =
    entry: e:
    let
      clean = builtins.removeAttrs e [
        "__denProvenance"
        "__denRegChain"
      ];
    in
    if e.__policyEffect != "include" then
      clean
    else
      clean
      // {
        __denProvenance =
          if entry.value.setsProvenance or false then
            e.__denProvenance or [ ]
          else
            lib.optional ((entry.value.provenance or null) != null) entry.value.provenance;
        __denRegChain = entry.value.chain or [ ];
      };

  # `include.at` (#694 §12): at the firing entity a plain include; at another
  # entity a delivery to it, the aspect resolved for its class at the firing
  # scope's context, as user-aspects delivers.
  placeAt =
    ctx: e:
    if e.__policyEffect != "include" || !(e ? __at) then
      e
    else
      let
        target = e.__at;
        firingKind = ctx.__entityKind or null;
        firing = if firingKind == null then null else ctx.${firingKind} or null;
        # The head names one of the instance's relata: an entity bound in the
        # policy's context.
        boundAs = lib.findFirst (
          k: builtins.isAttrs (ctx.${k} or null) && ctx.${k} ? name && sameEntity k ctx.${k} target
        ) null (builtins.filter (k: ((den.schema.${k} or { }).isEntity or false)) (builtins.attrNames ctx));
        atFiring = boundAs != null && boundAs == firingKind;
        class = e.__atClass or target.class or null;
      in
      if !(builtins.isAttrs target) || boundAs == null then
        throw "den: include.at names ${target.name or "an entity"}, which is not one of this policy instance's relata (bound in its context)"
      else if atFiring then
        builtins.removeAttrs e [
          "__at"
          "__atClass"
        ]
      else if class == null then
        throw "den: include.at names ${target.name or "an entity"}, which has no class to deliver into; give one with include.atClass"
      else
        den.lib.policy.provide {
          inherit class;
          receiver = target;
          module = _: den.lib.aspects.resolve class (den.lib.acceptance.atCtx ctx e.value);
        };

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
        placed = map (e: denProvenance entry (placeAt ctx (scrub entry e))) (
          validateEffects entry.name rawEffects
        );
        isInclude = e: e.__policyEffect == "include";
        # Includes are checked as written (a forward with a receiver),
        # provides and routes once aimed at the registrant.
        applied = applyToRegistrant entry.name (entry.value.registrant or null) ctx (
          lib.concatMap (
            e:
            if isInclude e then
              let
                r = pruneForwards ctx entry e.value;
              in
              lib.optional r.keep (e // { inherit (r) value; })
            else
              [ e ]
          ) placed
        );
      in
      {
        policyName = entry.name;
        # R3's host-class part of a registrant's own bare include is its own
        # content, not a delivery (§11a R7), so only the author's effects are
        # checked against admits.
        effects =
          builtins.filter (e: isInclude e || admitted ctx entry e) applied.effects ++ applied.registrantPart;
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
