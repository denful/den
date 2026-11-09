# Effect handler: emit-class
# Collects class modules into scope-partitioned buckets with dedup.
{ lib, den, ... }:
let
  # Everything emitted under a cross-provider include records the provider, so
  # the delivery can select exactly its modules (handlers/provenance.nix).
  inherit (import ./provenance.nix { inherit lib; }) sharedFanOutPrefix;
  inherit (import ./provenance.nix { inherit lib; }) stackTokenOf stackRegChainsOf;

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
        chain = ((state.scopedIncludesChain or (_: { })) null).${scope} or [ ];
        # A shared source's fan-out copy (bind.nix) is recorded under a token
        # naming the user it was fanned for: the fold drops it where that user
        # is accepted, whose own copy arrives (#694 §11a R6).
        provenance =
          if (param.sharedFanOutFor or null) != null then
            "${sharedFanOutPrefix}${param.sharedFanOutFor}"
          else
            stackTokenOf state scope;
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
              allLocChains = (state.scopedLocChains or (_: { })) null;
              updatedLocChains = allLocChains // {
                ${scope} = (allLocChains.${scope} or { }) // {
                  # A policy's emission carries where the policy registered, so
                  # a repeat deduplicated under a provider tags it as it tags
                  # the aspect's static content. Only untagged emissions: one
                  # under a provider is that provider's, innermost (§11a R7).
                  ${loc} = chain ++ lib.optionals (provenance == null) (stackRegChainsOf state scope);
                };
              };
            in
            state
            // {
              scopedClassImports = builtins.seq (forceHead updatedImports) (_: updatedImports);
              scopedEmittedLocs = builtins.seq (forceHead updatedEmittedLocs) (_: updatedEmittedLocs);
              scopedProvenanceLocs = builtins.seq (forceHead updatedProvenance) (_: updatedProvenance);
              # Each location's include chain at its first emission, read when a
              # repeat under a provide was deduplicated (handlers/provenance.nix).
              scopedLocChains = builtins.seq (forceHead updatedLocChains) (_: updatedLocChains);
            };
      };
  };
in
{
  inherit classCollectorHandler;
}
