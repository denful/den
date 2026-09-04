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

  # nameIndexed/nameAnon (children.nix) already stamp an unnamed or
  # synthetic-named sibling's walk position straight into its name —
  # "<parent>/<base>:<idx>" — precisely so it disambiguates without a
  # chain at all. Filling the chain for one of these too would encode
  # that same position twice (once in the name, once in
  # meta.aspect-chain), and the two copies compound multiplicatively
  # at every further level of nesting: each level's stamped name
  # already contains the whole rendered chain so far, then that name
  # becomes an element of the next level's filled chain, doubling it.
  # Detect the stamp by its mechanical ":<idx>" suffix rather than by
  # which synthetic marker produced it, since nameIndexed uses this
  # same shape for every marker (<anon>, <when>, ...).
  isWalkStampedName = n: builtins.match ".*:[0-9]+(/.*)?" n != null;

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
        aspect =
          if
            (withoutParametricKeys.meta.aspect-chain or null) == null
            && !(isWalkStampedName (withoutParametricKeys.name or "<anon>"))
          then
            withoutParametricKeys
            // {
              meta = (withoutParametricKeys.meta or { }) // {
                aspect-chain = parentChainSegments;
              };
            }
          else
            withoutParametricKeys;
        nodeIdentity = identity.key aspect;
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
        inherit state;
      };
  };
}
