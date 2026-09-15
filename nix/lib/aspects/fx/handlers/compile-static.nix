# Effect handler: compile-static
# Gates, classifies, emits classes, resolves nested keys, resolves children.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects) isMeaningfulName;
  inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;
  inherit (import ./gate-tag.nix { inherit fx; }) gateAndTag;

  inherit (import ../aspect { inherit lib den; } { inherit ctxFromHandlers; })
    registerConstraints
    ;

  parametricInternalKeys = [
    "__fn"
    "__args"
    "__parametricDepth"
    "__parametricResolvedArgs"
  ];

in
{
  compileStaticHandler = {
    "compile-static" =
      { param, state }:
      let
        raw = param.aspect;
        withoutParametricKeys = builtins.removeAttrs raw parametricInternalKeys;
        # An inline `includes = [ { name = ...; ... } ]` literal never gets a
        # declared chain (types.nix leaves meta.aspect-chain null there,
        # distinct from a genuine root's `[ ]`) — so two owners each writing
        # their own inline "tools" both read as root and collide at the gate.
        # Fill from the walk's current position, read here rather than in
        # the include walk: the walk's own stack frame can't force a child's
        # meta without cascading into its includes and grandchildren
        # synchronously, collapsing the fx trampoline; compile-static already
        # forces this node's own meta (via identity.key) at a point the
        # trampoline has deferred to, so filling here costs nothing extra.
        parentStack = ((state.scopedIncludesChainSegments or (_: { })) null).${state.currentScope} or [ ];
        # aspectPath appends a "{ctxId}" segment for context-bound nodes —
        # an instance marker, not an ancestor — so it must not end up inside
        # a written chain. Mirrors trace.nix's stripping of the same marker
        # shape on the rendered string form.
        parentChainSegments = builtins.filter (s: builtins.match "\\{.*" s == null) (
          if parentStack == [ ] then [ ] else lib.last parentStack
        );
        # Fill only where the chain is absent and the name is a real,
        # walk-independent one. A declared aspect referenced from two
        # different inclusion sites must keep its one identity — stamping
        # the inclusion site here instead would give it two and double-emit
        # it.
        #
        # __walkStamped (set by children.nix's nameAnon/nameIndexed) marks a
        # name invented from walk position rather than authored. Filling the
        # chain for one of these too would encode that same position twice
        # (once in the stamped name, once in meta.aspect-chain), and the two
        # copies compound multiplicatively at every further level of
        # nesting. Testing the marker, not the name's shape, means an
        # author's own name (e.g. "gcc:14") can never be mistaken for one.
        defPos = withoutParametricKeys.meta.__defPos or null;
        defValue = withoutParametricKeys.meta.__defValue or null;
        chainRegistry = ((state.chainByDefPos or (_: { })) null);
        # A position identifies a token, so it over-merges: a factory called
        # twice and `base // { ... }` specialised twice are two distinct
        # aspects at one position, and either can hold several distinct raw
        # values over the run — so each position keeps a list of claims, not
        # one. Reuse a claimed chain only when the raw authored value (the
        # whole value, `meta` included: `__defValue` is captured pre-stamp, so
        # there is nothing of the guard's own bookkeeping to strip) is the
        # same value as that claim's. One value included twice is
        # pointer-identical, which `==` settles without descending; two
        # distinct values stop at their first differing attribute.
        claimedEntries = if defPos == null then [ ] else chainRegistry.${defPos} or [ ];
        # K(K-1)/2 in K, the count of distinct raw values sharing one
        # position: the Nth arrival walks up to N-1 earlier claims before
        # adding its own. Bounded in practice because the registry is
        # per-run, so K only grows where one factory body is called many
        # times inside a single entity's resolve. (A prior figure recording
        # this as linear in K was measured against the single-claim form,
        # before distinct values got a claim each.)
        matchingClaim = lib.findFirst (
          e: defValue != null && e.value != null && defValue == e.value
        ) null claimedEntries;
        claimedChain = if matchingClaim == null then null else matchingClaim.chain;
        fillsChain =
          (withoutParametricKeys.meta.aspect-chain or null) == null
          && !(withoutParametricKeys.__walkStamped or false);
        # A shared let-bound value reports the same __defPos at every inclusion
        # site: the first node to fill here claims parentChainSegments for that
        # position, and every later node at the same position reuses the
        # claimed chain instead of filling its own — so both render one
        # identity and gate dedup collapses them to one emission. A node with
        # no __defPos (no author position, or the null the head-of-attrNames
        # fallback would have destroyed — see types.nix) behaves exactly as
        # the unregistered fill below.
        filledChain = if claimedChain != null then claimedChain else parentChainSegments;
        aspect =
          if fillsChain then
            withoutParametricKeys
            // {
              meta = (withoutParametricKeys.meta or { }) // {
                aspect-chain = filledChain;
              };
            }
          else
            withoutParametricKeys;
        nodeIdentity = identity.key aspect;
        nextState =
          if fillsChain && defPos != null && matchingClaim == null then
            let
              updated = chainRegistry // {
                ${defPos} = claimedEntries ++ [
                  {
                    chain = parentChainSegments;
                    value = defValue;
                  }
                ];
              };
            in
            state // { chainByDefPos = _: updated; }
          else
            state;
        # Pushed onto the walk's chain for descendants — identity.aspectPath,
        # not ownChain ++ [name], so this equals the list identity.key itself
        # renders (chainWrap derives its string the same way), and every
        # producer of a chain-push agrees on what a segment list means.
        chainSegments = identity.aspectPath aspect;
        isMeaningful = isMeaningfulName (aspect.name or "<anon>");
      in
      {
        resume =
          # Step 1: gate check (dedup + constraint) — skipped on parametric re-entry
          gateAndTag { inherit param aspect; } (
            tagged:
            # Step 2: probe for class handler, classify, emit, nest, resolve-children
            fx.bind (fx.effects.hasHandler "class") (
              hasClassHandler:
              fx.bind (if hasClassHandler then fx.send "class" null else fx.pure null) (
                targetClass:
                fx.bind
                  (fx.send "classify" {
                    aspect = tagged;
                    inherit targetClass;
                  })
                  (
                    classified:
                    # Nested keys are classified but never auto-walked.
                    # Sub-aspects must be explicitly included to emit class
                    # modules — this matches provides behavior and keeps
                    # activation explicit.
                    fx.bind
                      (fx.seq ([
                        (fx.send "emit-classes" {
                          aspect = tagged;
                          classKeys = classified.classKeys;
                          pipeKeys = classified.pipeKeys or [ ];
                          identity = nodeIdentity;
                        })
                        (registerConstraints tagged)
                      ]))
                      (
                        _:
                        fx.bind (fx.send "resolve-children" {
                          aspect = tagged;
                          inherit isMeaningful chainSegments;
                        }) (resolved: fx.pure [ resolved ])
                      )
                  )
              )
            )
          );
        state = nextState;
      };
  };
}
