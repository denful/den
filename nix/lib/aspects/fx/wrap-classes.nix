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

  # Process a single raw class entry through the wrapping pipeline.
  processEntry =
    enrichedCtx: class: entry:
    let
      enrichment = mergeEnrichment enrichedCtx entry.ctx;
      inherit (enrichment) enrichmentKeys ctx;
      result = den.lib.aspects.fx.aspect.wrapClassModule {
        inherit ctx;
        inherit (entry) module aspectPolicy globalPolicy;
      };
      finalModule = stripEnrichmentArgs {
        inherit (result) module wrapped;
        enrichmentOnlyKeys = builtins.attrNames enrichmentKeys;
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
      builtins.trace
        "den: class module ${class}@${nodeIdentity} skipped — context never provided: ${toString result.missingArgs}"
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
        entry: if !(entry.__rawEntry or false) then [ entry ] else processEntry enrichedCtx class entry
      ) entries
    ) classImports;
in
{
  inherit wrapCollectedClasses;
}
