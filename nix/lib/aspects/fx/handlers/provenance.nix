# Provenance of content a cross-provider include delivers (#694 F1).
# Den pushes the provider's token onto a den-only state stack around the
# include's walk (policy/apply.nix); what is emitted under it records the
# innermost token. Aspect names are never read: an author can set those.
{ lib }:
let
  stackAt = state: scope: ((state.scopedProvenanceStack or (_: { })) null).${scope} or [ ];
  # The innermost token den pushed at `scope`, or null.
  stackTokenOf =
    state: scope:
    let
      ts = stackTokensOf state scope;
    in
    if ts == [ ] then null else lib.last ts;
  # Every token den pushed at `scope`, outermost first.
  stackTokensOf = state: scope: lib.concatMap (f: f.tokens) (stackAt state scope);
  # The registration chains of the policies whose includes are being walked.
  stackRegChainsOf = state: scope: lib.concatMap (f: f.regChain) (stackAt state scope);
in
{
  inherit
    stackTokenOf
    stackTokensOf
    stackRegChainsOf
    ;
  sharedFanOutPrefix = "shared-fanout:";

  # A token's locations: those emitted under it, plus every location an aspect
  # walked first by another path emitted. That aspect was deduplicated under the
  # provide, so it is recorded by identity and matched through the chain each
  # location was emitted under, its own location included.
  locsOf =
    state:
    let
      direct = (state.scopedProvenanceLocs or (_: { })) null;
      deduped = (state.scopedProvenanceAspects or (_: { })) null;
      chains = (state.scopedLocChains or (_: { })) null;
      underAny =
        ids: loc: chain:
        builtins.any (id: lib.hasSuffix "@${id}" loc || builtins.elem id chain) ids;
      extra = scope: ids: builtins.attrNames (lib.filterAttrs (underAny ids) (chains.${scope} or { }));
    in
    {
      # Routes stood down because a transition default carries their content.
      __standDown = builtins.concatLists (
        builtins.attrValues ((state.scopedStandDowns or (_: { })) null)
      );
      __standDownProvides = builtins.concatLists (
        builtins.attrValues ((state.scopedStandDownProvides or (_: { })) null)
      );
    }
    // lib.recursiveUpdate direct (
      lib.mapAttrs (
        scope: byToken:
        lib.mapAttrs (token: ids: ((direct.${scope} or { }).${token} or [ ]) ++ extra scope ids) byToken
      ) deduped
    );
}
