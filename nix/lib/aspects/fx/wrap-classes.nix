{
  lib,
  den,
}:
let
  # Merge enrichment-only keys into the entry's emit-time ctx.
  # Only keys NOT already in entry.ctx are added — this avoids
  # overwriting entity bindings (host, user) from a different
  # scope while providing enrichment args (isNixos, isDarwin).
  mergeEnrichment =
    enrichedCtx: entryCtx:
    let
      enrichmentKeys = lib.filterAttrs (k: _: !(entryCtx ? ${k})) enrichedCtx;
    in
    {
      inherit enrichmentKeys;
      ctx = entryCtx // enrichmentKeys;
    };

  # Strip enrichment-only args from the module's advertised functionArgs.
  # Without this, NixOS probes _module.args.${name} for every advertised
  # arg and crashes when the key doesn't exist.
  # Wrapped modules: strip enrichment-only keys (injected by den).
  # Unwrapped modules: strip args with defaults not in ctx.
  stripEnrichmentArgs =
    {
      module,
      wrapped,
      enrichmentOnlyKeys,
      ctx,
    }:
    let
      isWrappedAttrset = builtins.isAttrs module && module ? __functionArgs;
      rawFuncArgs =
        if isWrappedAttrset then
          module.__functionArgs
        else if builtins.isFunction module then
          builtins.functionArgs module
        else
          { };
      argsToStrip =
        if wrapped then
          enrichmentOnlyKeys
        else
          # For unwrapped modules, strip args with defaults that aren't
          # in ctx (they're unknown to both den and NixOS).
          builtins.filter (k: rawFuncArgs.${k} or false && !(ctx ? ${k})) (builtins.attrNames rawFuncArgs);
      isFunction = builtins.isFunction module;
    in
    if argsToStrip == [ ] || (!isWrappedAttrset && !isFunction) then
      module
    else if isWrappedAttrset then
      module // { __functionArgs = removeAttrs rawFuncArgs argsToStrip; }
    else
      lib.setFunctionArgs module (removeAttrs rawFuncArgs argsToStrip);

  # Determine identity string and whether the node is anonymous.
  computeModuleIdentity =
    {
      entry,
      isContextDependent,
    }:
    let
      nodeIdentity = entry.identity or "<anon>";
      isAnon = den.lib.aspects.fx.identity.isAnonIdentity nodeIdentity;
      finalIdentity =
        if isContextDependent then
          nodeIdentity
        else
          den.lib.aspects.fx.identity.stripCtxSuffix nodeIdentity;
    in
    {
      inherit nodeIdentity isAnon finalIdentity;
    };

  # Apply location and key-based dedup wrapping to a module.
  wrapModule =
    {
      class,
      finalModule,
      isAnon,
      finalIdentity,
    }:
    let
      finalLoc = "${class}@${finalIdentity}";
    in
    if isAnon then
      lib.setDefaultModuleLocation finalLoc finalModule
    else
      {
        key = finalLoc;
        _file = finalLoc;
        imports = [ finalModule ];
      };

  # Construct the collision validator module.
  buildValidatorModule =
    {
      class,
      nodeIdentity,
      result,
    }:
    let
      validatorLoc = "${class}@${nodeIdentity}/<collision-validator>";
      validatorModule = lib.setFunctionArgs result.validator (
        result.validatorAdvertisedArgs or result.advertisedArgs or { }
      );
    in
    lib.setDefaultModuleLocation validatorLoc validatorModule;

  # Extract the base identity key from an entry identity.
  # Strips context suffix (/{ctxId}) but preserves full provider path.
  # "postgres" → "postgres", "provider/postgres" → "provider/postgres"
  # "postgres/{host=igloo}" → "postgres"
  baseIdentityFromEntry = id: den.lib.aspects.fx.identity.stripCtxSuffix id;

  # Apply per-aspect pipe overrides from __pipeTargeted.
  # Matches on full identity pathkey, not just leaf name.
  applyPipeTargeting =
    ctx: entry:
    let
      pipeTargeted = ctx.__pipeTargeted or { };
      entryId = entry.identity or "<anon>";
      baseId = baseIdentityFromEntry entryId;
      overrides = pipeTargeted.${baseId} or { };
    in
    if pipeTargeted == { } || overrides == { } then ctx else ctx // overrides;

  # Process a single raw class entry through the wrapping pipeline.
  processEntry =
    enrichedCtx: class: entry:
    let
      enrichment = mergeEnrichment (applyPipeTargeting enrichedCtx entry) entry.ctx;
      inherit (enrichment) enrichmentKeys ctx;
      result = den.lib.aspects.fx.aspect.wrapClassModule {
        inherit ctx class;
        inherit (entry) module aspectPolicy globalPolicy;
      };
      # Don't strip den arg keys that the wrapper intentionally advertises
      # for collision detection — NixOS needs to see them to pass _module.args.
      wrapperAdvertised = result.advertisedArgs or { };
      effectiveEnrichmentKeys = builtins.filter (k: !(wrapperAdvertised ? ${k})) (
        builtins.attrNames enrichmentKeys
      );
      finalModule = stripEnrichmentArgs {
        inherit (result) module wrapped;
        enrichmentOnlyKeys = effectiveEnrichmentKeys;
        inherit ctx;
      };
      isContextDependent = result.wrapped || (entry.isContextDependent or false);
      inherit (computeModuleIdentity { inherit entry isContextDependent; })
        nodeIdentity
        isAnon
        finalIdentity
        ;
      wrappedMod = wrapModule {
        inherit
          class
          finalModule
          isAnon
          finalIdentity
          ;
      };
      validatorMod = buildValidatorModule { inherit class nodeIdentity result; };
    in
    if result.unsatisfied or false then
      [ ]
    else
      [ wrappedMod ] ++ lib.optional (result ? validator) validatorMod;

  # Post-pipeline wrapping pass: wrap raw class entries using wrapClassModule
  # with the full enriched context. Non-raw entries pass through unchanged.
  wrapCollectedClasses =
    enrichedCtx: classImports:
    lib.mapAttrs (
      class: entries:
      lib.concatMap (
        entry:
        if entry.__isPipeEntry or false then
          [ entry ]
        else if !(entry.__rawEntry or false) then
          [ entry ]
        else
          processEntry enrichedCtx class entry
      ) entries
    ) classImports;
in
{
  inherit wrapCollectedClasses;
}
