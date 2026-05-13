# Policy result classification and effect extraction.
# Pure functions — no fx effects, no state.
{
  lib,
  schemaEntityKinds,
  schemaEntityKindsSet,
}:
let

  # Classify a resolve effect into schema vs enrichment (single-pass partition).
  classifyResolve =
    e:
    let
      keys = builtins.attrNames e.value;
      partitioned = lib.partition (k: schemaEntityKindsSet ? ${k}) keys;
      schemaKeys = partitioned.right;
      enrichKeys = partitioned.wrong;
      hasTarget = e.__targetKind or null != null;
    in
    if hasTarget then
      {
        schema = e;
        enrichment = null;
      }
    else if schemaKeys == [ ] then
      {
        schema = null;
        enrichment = e.value;
      }
    else if enrichKeys == [ ] then
      {
        schema = e;
        enrichment = null;
      }
    else
      {
        schema = e // {
          value = lib.genAttrs schemaKeys (k: e.value.${k});
        };
        enrichment = lib.genAttrs enrichKeys (k: e.value.${k});
      };

  # Extract effects of a given type from a policy result.
  filterEffect =
    kind: effects: builtins.filter (e: builtins.isAttrs e && (e.__policyEffect or "") == kind) effects;

  # Classify a single policy result into effect categories.
  classifyPolicyResult =
    r:
    let
      resolveEffects = builtins.filter (
        e: builtins.isAttrs e && (e.__policyEffect or "") == "resolve" && e.value != { }
      ) r.effects;
      resolveClassified = map classifyResolve resolveEffects;
    in
    {
      inherit (r) policyName;
      schemaEffects = builtins.filter (c: c.schema != null) resolveClassified;
      mergedEnrichment = builtins.foldl' (acc: c: acc // c.enrichment) { } (
        builtins.filter (c: c.enrichment != null) resolveClassified
      );
      includeEffects = filterEffect "include" r.effects;
      excludeEffects = filterEffect "exclude" r.effects;
      routeEffects = filterEffect "route" r.effects;
      instantiateEffects = filterEffect "instantiate" r.effects;
      provideEffects = filterEffect "provide" r.effects;
      pipeEffects = filterEffect "pipe" r.effects;
    };

  # Tag cross-provider schema effects with their paired includes.
  tagCrossProvider =
    r:
    let
      isCrossProvider =
        r.schemaEffects != [ ]
        && r.includeEffects != [ ]
        && builtins.any (se: se.schema.__targetKind or null != null) r.schemaEffects;
    in
    r // { inherit isCrossProvider; };

  # Check if a classified result has any effects.
  hasEffects =
    r:
    r.schemaEffects != [ ]
    || r.mergedEnrichment != { }
    || r.includeEffects != [ ]
    || r.excludeEffects != [ ]
    || r.routeEffects != [ ]
    || r.instantiateEffects != [ ]
    || r.provideEffects != [ ]
    || r.pipeEffects != [ ];

  # Collect all schema effects, attaching cross-provider includes and source policy name.
  collectSchemaEffects =
    paired:
    builtins.concatMap (
      r:
      map (
        se:
        se
        // {
          __sourcePolicyName = r.policyName;
        }
        // lib.optionalAttrs r.isCrossProvider {
          # Cross-provider includes are entity-scoped (attached to specific
          # schema resolve targets).  No <policy:*> tagging — they use normal
          # scope-prefixed dedup within their target entity's resolution.
          __policyIncludes = map (e: e.value) r.includeEffects;
        }
      ) r.schemaEffects
    ) paired;

  # Collect non-cross-provider include effects, tagged with source policy name.
  collectIncludeEffects =
    paired:
    builtins.concatMap (
      r:
      if r.isCrossProvider then
        [ ]
      else
        map (e: e // { __sourcePolicyName = r.policyName; }) r.includeEffects
    ) paired;

  # Extract tagged side-effects from classified policy results.
  extractTaggedEffects =
    classified:
    let
      paired = map tagCrossProvider classified;
    in
    {
      schemaEffects = collectSchemaEffects paired;
      includeEffects = collectIncludeEffects paired;
      excludeEffects = builtins.concatMap (r: r.excludeEffects) classified;
      routeEffects = builtins.concatMap (
        r: map (re: re // { __routePolicyName = r.policyName; }) r.routeEffects
      ) classified;
      instantiateEffects = builtins.concatMap (
        r: map (ie: ie // { __instantiatePolicyName = r.policyName; }) r.instantiateEffects
      ) classified;
      provideEffects = builtins.concatMap (
        r: map (pe: pe // { __providePolicyName = r.policyName; }) r.provideEffects
      ) classified;
      pipeEffects = builtins.concatMap (
        r: map (pe: pe // { __pipePolicyName = r.policyName; }) r.pipeEffects
      ) classified;
    };
in
{
  inherit
    classifyPolicyResult
    hasEffects
    extractTaggedEffects
    ;
}
