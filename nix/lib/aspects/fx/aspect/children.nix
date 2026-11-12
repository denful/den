# Walk an aspect's includes list — send each child through the resolve chain.
{
  lib,
  den,
}:
{ ctxFromHandlers }:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (import ./normalize.nix { inherit lib den; }) wrapChild isMeaningfulName;
  # resolveClaim: the shared cycle-guarded self-or-ancestor raw-value claim
  # lookup (also used by the constraint registry). registerPolicy reuses it
  # rather than a same-scope-only filter — see its comment for why. Also
  # shared with dispatch-policies.nix's raw-ref exclude resolution — see
  # registerConstraints's excludeList comment for why that's deferred there
  # rather than resolved here.
  inherit (import ../handlers/constraint.nix { inherit lib den; }) resolveClaim;
  inherit (import ./claim.nix { inherit lib den; }) claimPolicyNameAt;

  nameIndexed =
    state: base: idx: ctxId:
    let
      chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
      parent = if chain == [ ] then "<root>" else lib.last chain;
      suffix = if ctxId != null then "/${ctxId}" else "";
    in
    "${parent}/${base}:${toString idx}${suffix}";

  nameAnon = state: nameIndexed state "<anon>";

  # Synthetic names like "<when>" repeat per constructor; index them so
  # siblings don't dedup-collide at the gate.
  inherit (den.lib.aspects) isSyntheticName;

  # Wrap a computation in chain-push/chain-pop of the given position. Takes
  # the segment list alone and derives the rendered string from it — a single
  # carrier for one fact, so the string can never name a different position
  # than the list it was rendered from.
  chainWrap =
    nodeSegments: shouldPush: comp:
    if shouldPush then
      fx.bind (fx.send "chain-push" {
        identity = identity.pathKey nodeSegments;
        segments = nodeSegments;
      }) (_: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result)))
    else
      comp;

  propagateScope =
    parentScopeHandlers: parentCtxId: childSite: child:
    child
    // lib.optionalAttrs (parentScopeHandlers != null && !(child ? __scopeHandlers)) {
      __scopeHandlers = parentScopeHandlers;
    }
    // lib.optionalAttrs (parentCtxId != null && !(child ? __ctxId)) {
      __ctxId = parentCtxId;
    }
    // lib.optionalAttrs (childSite != null && !(child ? __policySite)) {
      __policySite = childSite;
    };

  # The include site below a parametric include: the include as written, and
  # the include positions under it. Every copy of one include is walked from
  # the same value, so its sites are equal under `==`, which compares a
  # function inside a container by pointer. Not the wrapped `__fn`: a functor's
  # is rebuilt on every walk (normalize.nix wrapFunctorChild).
  siteAt = site: idx: if site == null then null else site // { path = site.path ++ [ idx ]; };
  siteOf =
    parentSite: idx: rawChild: wrapped:
    if parentSite != null then
      siteAt parentSite idx
    else if wrapped ? __fn then
      {
        fn = rawChild;
        path = [ ];
      }
    else
      null;

  entityKinds = builtins.removeAttrs (den.schema or { }) [ "conf" ];

  # A policy record's site, with the entities bound where it is registered
  # that its `fn` doesn't take as arguments: those it can only have captured,
  # so copies made for different bindings stay apart.
  policySiteKey =
    site: scopeHandlers: p:
    if site == null then
      null
    else
      let
        taken = if lib.isFunction (p.fn or null) then lib.functionArgs p.fn else { };
        free = builtins.removeAttrs (builtins.intersectAttrs entityKinds (
          if scopeHandlers == null then { } else scopeHandlers
        )) (builtins.attrNames taken);
      in
      site // { free = lib.mapAttrs (_: e: e.id_hash or e.name or null) (ctxFromHandlers free); };

  dedupAndDispatch =
    child:
    fx.send "resolve" {
      aspect = child;
      identity = identity.key child;
      ctx = { };
    };

  # Route a single __isPolicy value to the policy registry. A policy's bare
  # `name` is the identity every other consumer already relies on (excludes,
  # cross-scope fired-tracking, broadcast dedup) — changing it unconditionally
  # would fix the collision below at the cost of every one of those. So the
  # bare name stays the identity in the overwhelming common case (one
  # registration per name per scope), and only a genuine collision — a
  # second, DIFFERENT record claiming a name already taken — gets displaced
  # to a chain-qualified identity instead of silently overwriting the first
  # (scopedAspectPolicies merges by overwrite, one dict per scope).
  #
  # Claims are bucketed by bare name, not by definition position (Task 4c's
  # registry for aspects): traced empirically, two aspects each declaring
  # their own "policies.tools" merge at DIFFERENT option paths — each
  # aspect's own submodule eval bakes its own name into `loc` — so a
  # def-position bucket puts them in separate buckets and misses the
  # collision entirely, even though both still land in one scope's
  # scopedAspectPolicies. Whole-value equality is what actually tells "one
  # shared policy referenced twice" (O5, must merge into one identity) apart
  # from "two distinct same-named policies" (O4, must split).
  #
  # "Same scope" for that comparison means self-or-ancestor (foldScopeAncestors
  # over scopeParent), not `e.scope == scope`: the late-policy dispatch
  # (policy/schema.nix emitLateForSibling) merges a parent scope's
  # registrations with a descendant sibling's BY THIS SAME ownerIdentity
  # (`allAspectPolicies = scopedAspectPolicies.${parentScope} //
  # scopedAspectPolicies.${sib.scopeId}`) — a same-scope-only filter let a
  # host-scope "tools" and a distinct descendant-scope "tools" both keep the
  # bare name and collide at that merge.
  #
  # A displaced identity is qualified with the claim's own index within its
  # bucket, not just the parent chain: every claimant sharing one parent
  # chain (e.g. three factory-built policies included as siblings) shares
  # the SAME chain segments, so without the index the second and third (and
  # every later) distinct claimant would collide with EACH OTHER under one
  # identical qualified string.
  # One of den's channels (#694 §12): its `fn` is defined in one of den's
  # channel files (an author can't place a definition there), or it is one of
  # den's home environments' policies or den's one `den.policies` channel,
  # user-to-host, by value. A home environment built with makeHomeEnv shares
  # den's file, so it is matched by record. A record extended with
  # `//` keeps its `fn`'s position: `den.batteries.define-user // { … }` that
  # keeps den's `fn` is still den's channel, by design; one that redefines
  # `fn` is the author's.
  denChannelFiles = map (f: "${toString ../../../../..}/${f}") [
    "modules/aspects/batteries/define-user.nix"
    "modules/aspects/batteries/primary-user.nix"
    "modules/aspects/batteries/user-shell.nix"
    "modules/aspects/batteries/unfree/unfree.nix"
    "modules/aspects/batteries/insecure/insecure.nix"
  ];
  # Den's home environments' records, at their fixed keys only: a key a
  # config declares is never read.
  denEnvChannels =
    let
      ci = den.internal.channelPolicies or { };
    in
    lib.concatMap (k: ci.${k} or [ ]) [
      "homeManager"
      "hjem"
      "maid"
    ];
  isDenChannel =
    p:
    let
      pos = builtins.unsafeGetAttrPos "fn" p;
    in
    (pos != null && builtins.elem pos.file denChannelFiles)
    || builtins.elem p denEnvChannels
    || p == (den.policies.user-to-host or null);

  # Den's own delivery fields (#694's mutual-provider and stand-down routes)
  # are honoured only on effects of a policy defined in a den file that sets
  # them; an author can't place a definition there.
  denMadeFiles = map (f: "${toString ../../../../..}/${f}") [ "nix/lib/home-env.nix" ];
  isDenMade =
    p:
    let
      pos = builtins.unsafeGetAttrPos "fn" p;
    in
    pos != null && builtins.elem pos.file denMadeFiles;

  registerPolicy =
    site: p:
    claimPolicyNameAt site p.name p (
      ownerIdentity:
      fx.send "register-aspect-policy" {
        inherit (p) fn;
        inherit ownerIdentity;
        # The record's own `fn` slot, shared by every copy of the record: two
        # registrations of one record compare equal under `==`, two records
        # sharing a name don't (policy/schema.nix samePolicy).
        fnSlot = builtins.intersectAttrs { fn = null; } p;
        displayName = p.name;
        ref = p;
        denChannel = isDenChannel p;
        denMade = isDenMade p;
      }
    );

  isPolicy = v: builtins.isAttrs v && v.__isPolicy or false;

  # Den's provenance wrappers (#694) are named with this marker; an author's
  # aspect may not be. Den's own are told apart by where their `name` is
  # defined, which an author can't place.
  provenanceMarker = "den-provides-to-host=";
  provenanceMarkerLength = builtins.stringLength provenanceMarker;
  denWrapperFiles = map (f: "${toString ../../../../..}/${f}") [
    "nix/lib/aspects/fx/aspect/provide.nix"
    "nix/lib/aspects/fx/policy/dispatch.nix"
  ];
  isDenProvenanceWrapper =
    v:
    let
      pos = if builtins.isAttrs v then builtins.unsafeGetAttrPos "name" v else null;
    in
    pos != null && builtins.elem pos.file denWrapperFiles;

  processInclude =
    {
      parentScopeHandlers,
      parentCtxId,
      parentSite,
      skipNameAnon,
    }:
    idx: rawChild:
    let
      registerAt = i: p: registerPolicy (policySiteKey (siteAt parentSite i) parentScopeHandlers p) p;
    in
    # Route policy values to register-aspect-policy instead of aspect walk.
    if isPolicy rawChild then
      registerAt idx rawChild
    else if builtins.isList rawChild then
      let
        policyRegistrations = lib.concatLists (
          lib.imap0 (i: item: lib.optional (isPolicy item) (registerAt (idx * 100 + i) item)) rawChild
        );
        nonPolicyItems = builtins.filter (item: !isPolicy item) rawChild;
        recurse = processInclude {
          inherit
            parentScopeHandlers
            parentCtxId
            parentSite
            skipNameAnon
            ;
        };
      in
      fx.bind (fx.seq policyRegistrations) (
        _:
        if nonPolicyItems == [ ] then
          fx.pure [ ]
        else
          fx.seq (lib.imap0 (i: item: recurse (idx * 100 + i) item) nonPolicyItems)
      )
    else
      # Existing behavior: wrap and dispatch as aspect.
      let
        wrapped = wrapChild rawChild;
        withScope = propagateScope parentScopeHandlers parentCtxId (siteOf parentSite idx rawChild
          wrapped
        ) wrapped;
      in
      fx.bind fx.effects.state.get (
        state:
        let
          childName = withScope.name or "<anon>";
          # __walkStamped records that the name below was invented from walk
          # position, not authored — compile-static reads it to decide
          # whether filling meta.aspect-chain here would double-encode the
          # same position (once in the stamped name, once in the chain).
          # A marker set here, rather than a shape compile-static infers from
          # the name, can't be confused with an author's own name choice.
          child =
            if
              builtins.substring 0 provenanceMarkerLength childName == provenanceMarker
              && !(isDenProvenanceWrapper rawChild)
            then
              throw "den: aspect name `${childName}` is reserved: names beginning `${provenanceMarker}` are den's provenance wrappers"
            else if skipNameAnon then
              withScope
            else if !(isMeaningfulName childName) then
              withScope
              // {
                name = nameAnon state idx (withScope.__ctxId or null);
                __walkStamped = true;
              }
            else if isSyntheticName childName then
              withScope
              // {
                name = nameIndexed state childName idx (withScope.__ctxId or null);
                __walkStamped = true;
              }
            else
              withScope;
        in
        dedupAndDispatch child
      );

  emitIncludes =
    {
      __parentScopeHandlers ? null,
      __parentCtxId ? null,
      __parentPolicySite ? null,
      __skipNameAnon ? false,
    }:
    incs:
    let
      processOne = processInclude {
        parentScopeHandlers = __parentScopeHandlers;
        parentCtxId = __parentCtxId;
        parentSite = __parentPolicySite;
        skipNameAnon = __skipNameAnon;
      };
      len = builtins.length incs;
      go =
        idx: acc:
        if idx >= len then
          acc
        else
          go (idx + 1) (
            fx.bind acc (
              results:
              fx.bind (processOne idx (builtins.elemAt incs idx)) (
                childResults: fx.pure ([ childResults ] ++ results)
              )
            )
          );
    in
    fx.bind (go 0 (fx.pure [ ])) (
      revChunks: fx.pure (builtins.concatLists (lib.reverseList revChunks))
    );

  # A policy record's exclude: by its name, resolved by value (rawRef) once the
  # claim registry holds it (handlers/constraint.nix isPolicyExcluded).
  policyExcludeOf = ref: {
    type = "exclude";
    scope = "subtree";
    identity = ref.name;
    rawRef = ref;
  };

  registerConstraints =
    aspect:
    let
      rawHandleWith = aspect.meta.handleWith or null;
      # Flattened for the same reason `includes` is (fx/aspect.nix): `providerType`
      # names a list of policy records as a valid element, so `excludes = [ [ p ] ]`
      # type-checks. Unflattened it reached `identity.key` as a list, which yields
      # "<anon>" and excludes nothing — the silent no-op #3c5b5227 closed for bare
      # strings, still open over the shape that commit's own type admits.
      rawExcludes = lib.flatten (aspect.excludes or [ ]);
      handleWithList =
        if rawHandleWith == null then
          [ ]
        else if builtins.isList rawHandleWith then
          rawHandleWith
        else if builtins.isAttrs rawHandleWith then
          [ rawHandleWith ]
        else
          [ ];
      # Compute exclude identity, normalizing content wrappers that have
      # __aspectChain but no name (nested keys without _ prefix).
      excludeIdentity =
        ref:
        if builtins.isAttrs ref && ref.__isPolicy or false then
          ref.name
        else if builtins.isAttrs ref && ref ? __aspectChain && !(ref ? name) then
          let
            prov = ref.__aspectChain;
          in
          identity.key {
            name = if prov != [ ] then lib.last prov else "<anon>";
            meta.aspect-chain = if prov != [ ] then lib.init prov else [ ];
          }
        else
          identity.key ref;
      # A policy exclude's `identity` is still only a bare-name guess (kept
      # as a fallback storage key — see the __isPolicy branch above): this
      # aspect's own registerConstraints runs BEFORE its includes are
      # walked (compile-static sequences registerConstraints ahead of
      # resolve-children's emitIncludes), so the claim registry a raw-value
      # lookup would need is measurably still empty here — traced empirically,
      # `state.policyClaimsByName."name:<bucket>"` reads `{ }` at this exact
      # point even though the excluded record's own self-equality already
      # compares true (`ref == ref`). rawRef carries the record itself so
      # constraint.nix's isPolicyExcluded (shared by dispatch-policies.nix's
      # initial dispatch and policy/schema.nix's late-sibling re-dispatch)
      # can resolve it later, once dispatch has run past this aspect's own
      # includes and the registry actually holds the claim.
      policyExclude = policyExcludeOf;
      excludeList = map (
        ref:
        {
          type = "exclude";
          scope = "subtree";
          identity = excludeIdentity ref;
        }
        // lib.optionalAttrs (builtins.isAttrs ref && ref.__isPolicy or false) { rawRef = ref; }
        // lib.optionalAttrs (builtins.isAttrs ref && ref ? __transitionDefaultPolicy) {
          defaultPolicy = ref.__transitionDefaultPolicy;
        }
        # An aspect value names the aspect written there, not every aspect
        # sharing its name: an inline `{ name = "tools"; … }` elsewhere is
        # another aspect (constraint.nix sameDefinition).
        // lib.optionalAttrs (builtins.isAttrs ref && !(ref.__isPolicy or false) && ref ? meta) {
          refDefPos = ref.meta.__defPos or null;
        }
      ) rawExcludes;
      owner = aspect.name or "<anon>";
      send =
        ownerChain: c:
        fx.send "register-constraint" (
          c // { inherit owner; } // lib.optionalAttrs (ownerChain != null) { inherit ownerChain; }
        );
    in
    fx.bind (ownerChainOverride { excludes = false; } aspect) (
      filterChain:
      fx.bind (ownerChainOverride { excludes = true; } aspect) (
        excludeChain:
        fx.bind (fx.seq (map (send filterChain) handleWithList ++ map (send excludeChain) excludeList)) (
          _: registerIncludedPolicyExcludes excludeChain aspect
        )
      )
    );

  # A coerced parametric body (types.nix ownBody) is walked as a child of its
  # aspect, one chain segment deeper; its constraints are the aspect's own, so
  # they register at the aspect's chain. null keeps the handler's default.
  ownerChainOverride =
    { excludes }:
    aspect:
    # A host's own aspect (`den.aspects.<host>`, resolve-entity.nix's
    # self-provide, and its own parametric body) registers its excludes at the
    # host root, as the host instance's `excludes` do: they reach all of the
    # host's content, its users' included. Its `handleWith` keeps the
    # aspect's reach.
    if excludes && aspect.__excludesAtEntity or false then
      fx.pure [ ]
    else if aspect.__ownBody or false then
      fx.bind fx.effects.state.get (
        state:
        let
          chain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
        in
        fx.pure (if chain == [ ] then null else lib.init chain)
      )
    else
      fx.pure null;

  # A policy listed in an aspect's `includes` fires only at the scope's dispatch,
  # after the aspect's static includes have already passed the gate, and its
  # exclude would then reach only what the policy itself includes. So an
  # `exclude` it returns is registered here as well, beside the aspect's own
  # `excludes`: before any include is gated, with the includer's subtree as
  # reach. A policy whose arguments this scope does not supply yet is left to
  # its dispatch.
  registerIncludedPolicyExcludes =
    ownerChain: aspect:
    let
      policies = builtins.filter isPolicy (lib.flatten (aspect.includes or [ ]));
    in
    if policies == [ ] then
      fx.pure null
    else
      fx.bind fx.effects.state.get (
        state:
        let
          scope = state.currentScope or null;
          scopeCtx = if scope == null then { } else ((state.scopeContexts or (_: { })) null).${scope} or { };
          ctx0 = scopeCtx // den.lib.aspects.fx.aspect.ctxFromHandlers (aspect.__scopeHandlers or { });
          ctx = ctx0 // {
            self = ctx0.self or ctx0;
          };
          effectsOf =
            p: if den.lib.synthesizePolicies.resolveArgsSatisfied p.fn ctx then lib.toList (p.fn ctx) else [ ];
          excludes = builtins.filter (e: builtins.isAttrs e && (e.__policyEffect or "") == "exclude") (
            builtins.concatMap effectsOf policies
          );
        in
        fx.seq (
          map (
            e:
            fx.send "register-constraint" (
              {
                type = "exclude";
                scope = "subtree";
                identity = identity.key e.value;
                owner = "policy";
              }
              // lib.optionalAttrs (ownerChain != null) { inherit ownerChain; }
              // lib.optionalAttrs (e.value.__isPolicy or false) { rawRef = e.value; }
              # Named by the aspect written there, as excludeList names it.
              //
                lib.optionalAttrs (builtins.isAttrs e.value && !(e.value.__isPolicy or false) && e.value ? meta)
                  {
                    refDefPos = e.value.meta.__defPos or null;
                  }
              # A battery's transition default is excluded with it, as excludeList
              # pairs it (#694, until removalDate).
              // lib.optionalAttrs (builtins.isAttrs e.value && e.value ? __transitionDefaultPolicy) {
                defaultPolicy = e.value.__transitionDefaultPolicy;
              }
            )
          ) excludes
        )
      );
in
{
  inherit emitIncludes registerConstraints chainWrap;
}
