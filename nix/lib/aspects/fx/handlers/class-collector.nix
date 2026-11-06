# Effect handler: emit-class
# Collects class modules into scope-partitioned buckets with dedup.
{ lib, den, ... }:
let
  # The chain-push identity of a cross-provider include's wrapper starts with
  # this marker (aspect/provide.nix); everything emitted under it records the
  # provider so the delivery can select exactly its modules.
  provenanceMarker = "den-provides-to-host=";
  provenanceOf =
    chain:
    let
      hits = builtins.filter (lib.hasInfix provenanceMarker) chain;
    in
    if hits == [ ] then null else lib.last (lib.splitString provenanceMarker (builtins.head hits));

  classCollectorHandler = {
    "emit-class" =
      { param, state }:
      let
        nodeIdentity = param.identity or "<anon>";
        isRawEntry = param.__rawEntry or false;
        baseIdentity =
          if param.isContextDependent or false then
            nodeIdentity
          else
            den.lib.aspects.fx.identity.stripCtxSuffix nodeIdentity;
        loc = "${param.class}@${baseIdentity}";
        mod =
          if isRawEntry then
            param // { __loc = loc; }
          else if den.lib.aspects.fx.identity.isAnonIdentity nodeIdentity then
            den.lib.setDefaultModuleLocation loc param.module
          else
            {
              key = loc;
              _file = loc;
              imports = [ param.module ];
            };
        scope = state.currentScope;
        emittedLocs = (state.scopedEmittedLocs or (_: { })) null;
        scopeLocs = emittedLocs.${scope} or { };
        alreadyEmitted = scopeLocs ? ${loc};
        provenance = provenanceOf (((state.scopedIncludesChain or (_: { })) null).${scope} or [ ]);
        allProvenance = (state.scopedProvenanceLocs or (_: { })) null;
        # Recorded on a skipped emission too: content provided and also reached
        # another way still crosses, since the other path does not revoke the
        # provide's edge.
        updatedProvenance =
          if provenance == null then
            allProvenance
          else
            allProvenance
            // {
              ${scope} = (allProvenance.${scope} or { }) // {
                ${provenance} = ((allProvenance.${scope} or { }).${provenance} or [ ]) ++ [ loc ];
              };
            };
      in
      {
        resume = null;
        state =
          if alreadyEmitted then
            if provenance == null then
              state
            else
              state
              // {
                scopedProvenanceLocs = builtins.seq (builtins.attrNames updatedProvenance) (_: updatedProvenance);
              }
          else
            let
              allImports = state.scopedClassImports null;
              scopeImportData = allImports.${scope} or { };
              updatedImports = allImports // {
                ${scope} = scopeImportData // {
                  ${param.class} = (scopeImportData.${param.class} or [ ]) ++ [ mod ];
                };
              };
              updatedEmittedLocs = emittedLocs // {
                ${scope} = scopeLocs // {
                  ${loc} = true;
                };
              };
              # These two maps are threaded as `_: value` closures so the effect loop's state
              # deepSeq cannot reach the module bodies inside them (den's lazy-state discipline).
              # The shield is total, so each emit-class layered a fresh lazy `prev // { ... }`;
              # forcing the final map then chained through every prior closure — depth ∝ emit
              # count, a C-stack overflow on large fleets. Force just the TOP-LEVEL spine (the
              # scope key set — bounded by fleet size, never the module lists) at each step so
              # the closure captures an already-evaluated head: the chain collapses to O(1) depth
              # per force while the bodies stay unforced. `seq (attrNames m)` is O(scopes), so the
              # accumulation stays linear.
              forceHead = m: builtins.seq (builtins.attrNames m) m;
            in
            state
            // {
              scopedClassImports = builtins.seq (forceHead updatedImports) (_: updatedImports);
              scopedEmittedLocs = builtins.seq (forceHead updatedEmittedLocs) (_: updatedEmittedLocs);
              scopedProvenanceLocs = builtins.seq (forceHead updatedProvenance) (_: updatedProvenance);
            };
      };
  };
in
{
  inherit classCollectorHandler;
}
