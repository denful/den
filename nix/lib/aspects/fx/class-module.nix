{
  lib,
  den,
  ...
}:
let
  # Resolve collision policy from three levels: aspect meta → entity → global.
  # Shared by wrapClassModule (specialArgs collisions) and mkCollisionDetector
  # (_module.args collisions).
  # Build a collision-check validator module from a policy resolver and
  # the list of den arg names to check. Returns a module function that
  # probes config._module.args for each name and emits warnings/errors.
  mkCollisionValidator =
    policy: denArgNames: moduleArgs:
    let
      collisionChecks = lib.concatMap (
        name:
        let
          mArgs = moduleArgs.config._module.args or { };
          hasReal =
            (builtins.tryEval (builtins.seq (mArgs.${name} or null) (mArgs ? ${name}))).value or false;
          p = policy name;
        in
        if !hasReal then
          [ ]
        else if p == "error" then
          throw "den: class module arg '${name}' collides with module-system arg — set collisionPolicy to resolve"
        else if p == "class-wins" then
          [
            "den: class module arg '${name}' collision — class-wins, den value dropped"
          ]
        else
          [
            "den: class module arg '${name}' collision — den-wins, module-system value shadowed"
          ]
      ) denArgNames;
    in
    {
      warnings = collisionChecks;
    };

  resolveCollisionPolicy =
    {
      ctx,
      aspectPolicy,
      globalPolicy,
    }:
    name:
    if aspectPolicy != null then
      aspectPolicy
    else if
      builtins.isAttrs (ctx.${name} or null)
      && (ctx.${name} ? collisionPolicy)
      && ctx.${name}.collisionPolicy != null
    then
      ctx.${name}.collisionPolicy
    else
      # Check __collisionPolicies — pre-computed from schema entries during
      # resolveEntity to avoid circular eval through module system configs.
      let
        policies = ctx.__collisionPolicies or { };
      in
      if policies ? ${name} then policies.${name} else globalPolicy;

  # Class modules (after aspectContentType unwrapping or from deferred
  # imports) may be { imports = [...]; } attrsets. The original function
  # is nested inside.  We recursively descend into imports to find and
  # wrap any functions that request den context args.
  wrapDeferredImports =
    args: imports:
    let
      go =
        imp:
        if builtins.isFunction imp then
          let
            result = wrapClassModule (args // { module = imp; });
          in
          {
            inherit (result) wrapped;
            value = result.module;
          }
        else if builtins.isAttrs imp && imp ? imports then
          let
            inner = map go imp.imports;
            anyWrapped = builtins.any (r: r.wrapped) inner;
          in
          {
            wrapped = anyWrapped;
            value = imp // {
              imports = map (r: r.value) inner;
            };
          }
        else
          {
            wrapped = false;
            value = imp;
          };
      results = map go imports;
      anyWrapped = builtins.any (r: r.wrapped) results;
    in
    {
      wrapped = anyWrapped;
      imports = map (r: r.value) results;
    };

  # Wrap a function module with den context args (partial application + collision handling).
  wrapFunctionModule =
    {
      module,
      ctx,
      aspectPolicy,
      globalPolicy,
      class ? null,
    }:
    let
      allArgs = builtins.functionArgs module;
      argNames = builtins.attrNames allArgs;
      denArgNames = builtins.filter (k: ctx ? ${k}) argNames;
      schemaKinds = den.lib.schemaUtil.schemaArgKinds;
      missingDenArgNames = builtins.filter (k: builtins.elem k schemaKinds && !(allArgs.${k} or false)) (
        builtins.filter (k: !(ctx ? ${k})) argNames
      );
      warnedModule = builtins.foldl' (
        mod: k: lib.warn "den: class module requests '${k}' but no ${k} context is available" mod
      ) module missingDenArgNames;
    in
    if missingDenArgNames != [ ] then
      {
        module = warnedModule;
        wrapped = false;
        unsatisfied = true;
        missingArgs = missingDenArgNames;
      }
    else if denArgNames == [ ] then
      {
        module = warnedModule;
        wrapped = false;
      }
    else
      let
        denArgs = lib.genAttrs denArgNames (k: ctx.${k});
        remainingArgs = removeAttrs allArgs denArgNames;

        # Detect pipe args containing config thunk markers (__configThunk).
        # These are resolved inside the module wrapper using the evalModules
        # fixpoint config, breaking the circular dependency with assemblePipes.
        pipeThunks = ctx.__pipeConfigThunks or { };
        denArgsWithThunks = builtins.filter (k: pipeThunks ? ${k}) denArgNames;
        hasConfigThunks = denArgsWithThunks != [ ];

        # The consuming scope's own user/home name — a producer marker for the
        # same member resolves against `config` directly (standalone-safe).
        consumerName = ctx.user.name or ctx.home.name or null;

        # A class's parentPath/parentArg (registered by its battery) describe how
        # its members nest into the enclosing config-owner — null for root
        # classes (nixos, darwin, …). parentPath is the single "does this nest"
        # signal; parentArg is the module arg by which a member reaches the owner.
        classParentPath = c: if c != null && den.classes ? ${c} then den.classes.${c}.parentPath else null;
        classParentArg = c: if c != null && den.classes ? ${c} then den.classes.${c}.parentArg else null;
        consumerNested = (classParentPath class) != null;
        consumerParentArg = classParentArg class;

        # Each deferred thunk is handed `config` (its PRODUCER class config) and,
        # for a nested producer, the OWNER config under the producer class's
        # parentArg. A nested consumer fetches the owner config from the module
        # system via its own parentArg — requested only when a marker needs it (a
        # root-class producer, a different member, or a thunk reading its
        # parentArg) — never for a pure same-member thunk, so standalone members
        # (no owner arg) keep working.
        allMarkers = builtins.filter (v: v ? __configThunk) (
          lib.concatMap (k: ctx.${k} or [ ]) denArgsWithThunks
        );
        markerNeedsOwner =
          m:
          let
            pa = classParentArg (m.__producerClass or null);
          in
          (classParentPath (m.__producerClass or null)) == null
          || (m.__producerName or null) != consumerName
          || (pa != null && (builtins.functionArgs (m.__fn or (_: { }))) ? ${pa});
        needsOwner = consumerNested && hasConfigThunks && builtins.any markerNeedsOwner allMarkers;

        # If any den args have config thunks, we need `config` (and possibly the
        # owner config, via the consumer's parentArg) from the module system to
        # resolve them — force the wrapper path even if no other remaining args.
        effectiveRemainingArgs =
          if hasConfigThunks then
            remainingArgs
            // {
              config = true;
            }
            // lib.optionalAttrs (needsOwner && consumerParentArg != null) { ${consumerParentArg} = true; }
          else
            remainingArgs;

        # Resolve config thunk markers against the PRODUCING class+scope's config
        # (not the consuming module's): a root-class producer → the owner config
        # (the consumer's `config` for a root class, else the fetched owner); a
        # nested producer → its config at the registered parentPath of the owner.
        resolveMarkers =
          config: owner: values:
          let
            ownerCfg = if consumerNested then owner else config;
          in
          builtins.concatMap (
            v:
            if v ? __configThunk then
              let
                thunkArgs = builtins.functionArgs v.__fn;
                ctxArgs = lib.genAttrs (builtins.filter (k: ctx ? ${k}) (builtins.attrNames thunkArgs)) (
                  k: ctx.${k}
                );
                pcls = v.__producerClass or null;
                pPath = classParentPath pcls;
                pArg = classParentArg pcls;
                producerConfig =
                  if pcls == null then
                    config
                  else if pPath == null then
                    ownerCfg
                  else if consumerNested && pcls == class && (v.__producerName or null) == consumerName then
                    config
                  else
                    lib.attrByPath (pPath v.__producerName) { } ownerCfg;
                result = v.__fn (
                  ctxArgs
                  // {
                    config = producerConfig;
                  }
                  // lib.optionalAttrs (pArg != null) { ${pArg} = ownerCfg; }
                  // {
                    inherit lib;
                  }
                );
              in
              if builtins.isList result then result else [ result ]
            else
              [ v ]
          ) values;
      in
      if effectiveRemainingArgs == { } then
        {
          module = warnedModule denArgs;
          wrapped = true;
        }
      else
        let
          policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
          classWinsNames = builtins.filter (name: policy name == "class-wins") denArgNames;
          classWinsDen = lib.genAttrs classWinsNames (k: denArgs.${k});
          denWinsDen = removeAttrs denArgs classWinsNames;
          wrapper =
            moduleArgs:
            let
              # A nested consumer fetches the owner config from the module system
              # via its registered parentArg (e.g. home-manager's osConfig).
              ownerCfg =
                if consumerNested && consumerParentArg != null then
                  (moduleArgs.${consumerParentArg} or { })
                else
                  (moduleArgs.config or { });
              resolvedDen =
                if hasConfigThunks then
                  lib.mapAttrs (
                    k: v:
                    if builtins.elem k denArgsWithThunks && builtins.isList v then
                      resolveMarkers (moduleArgs.config or { }) ownerCfg v
                    else
                      v
                  ) denWinsDen
                else
                  denWinsDen;
            in
            warnedModule (classWinsDen // moduleArgs // resolvedDen);
          validatorAdvertisedArgs = effectiveRemainingArgs // {
            config = true;
          };
          validator = mkCollisionValidator policy denArgNames;
          advertisedArgs = effectiveRemainingArgs // lib.genAttrs denArgNames (_: true);
        in
        {
          module = lib.setFunctionArgs wrapper advertisedArgs;
          inherit validator validatorAdvertisedArgs advertisedArgs;
          wrapped = true;
        };

  # Wrap an attrset-with-imports module (recurses into imports for function wrapping).
  wrapImportsModule =
    {
      module,
      ctx,
      aspectPolicy,
      globalPolicy,
      class ? null,
    }:
    let
      result = wrapDeferredImports {
        inherit
          ctx
          aspectPolicy
          globalPolicy
          class
          ;
      } module.imports;
      policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
      denArgNames = builtins.attrNames ctx;
      validator = mkCollisionValidator policy denArgNames;
    in
    {
      module = module // {
        inherit (result) imports;
      };
      inherit (result) wrapped;
    }
    // lib.optionalAttrs (result.wrapped && ctx != { }) {
      inherit validator;
      validatorAdvertisedArgs.config = true;
      advertisedArgs = lib.genAttrs denArgNames (_: true);
    };

  wrapClassModule =
    args:
    if builtins.isAttrs args.module && args.module ? imports then
      wrapImportsModule args
    else if !builtins.isFunction args.module then
      {
        inherit (args) module;
        wrapped = false;
      }
    else
      wrapFunctionModule args;
in
{
  inherit wrapClassModule;
}
