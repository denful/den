# Provenance of content a cross-provider include delivers (#694 F1).
# The include's wrapper (aspect/provide.nix) puts a marker on the include chain;
# what is emitted under it records the provider's token.
{ lib }:
let
  marker = "den-provides-to-host=";

  tokenOf =
    chain:
    let
      hits = builtins.filter (lib.hasInfix marker) chain;
    in
    if hits == [ ] then null else lib.last (lib.splitString marker (builtins.head hits));
in
{
  inherit tokenOf;

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
    lib.recursiveUpdate direct (
      lib.mapAttrs (
        scope: byToken:
        lib.mapAttrs (token: ids: ((direct.${scope} or { }).${token} or [ ]) ++ extra scope ids) byToken
      ) deduped
    );
}
