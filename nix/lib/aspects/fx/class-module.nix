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
      globalPolicy;

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

  wrapClassModule =
    {
      module,
      ctx,
      aspectPolicy,
      globalPolicy,
    }:
    if builtins.isAttrs module && module ? imports then
      let
        result = wrapDeferredImports {
          inherit
            ctx
            aspectPolicy
            globalPolicy
            ;
        } module.imports;
        policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
        denArgNames = builtins.attrNames ctx;
        advertisedArgs = lib.genAttrs denArgNames (_: true);
        validatorAdvertisedArgs = {
          config = true;
        };
        validator = mkCollisionValidator policy denArgNames;
      in
      {
        module = module // {
          imports = result.imports;
        };
        inherit (result) wrapped;
      }
      // lib.optionalAttrs (result.wrapped && ctx != { }) {
        inherit validator validatorAdvertisedArgs advertisedArgs;
      }
    else if !builtins.isFunction module then
      {
        inherit module;
        wrapped = false;
      }
    else
      let
        allArgs = builtins.functionArgs module;
        argNames = builtins.attrNames allArgs;
        denArgNames = builtins.filter (k: ctx ? ${k}) argNames;
        # Only warn for args matching known schema kinds that have no default.
        # Avoids false warnings on module-system args (config, pkgs, etc.).
        schemaKinds = den.lib.schemaUtil.schemaArgKinds;
        missingDenArgNames = builtins.filter (k: builtins.elem k schemaKinds && !(allArgs.${k} or false)) (
          builtins.filter (k: !(ctx ? ${k})) argNames
        );
        # Emit warnings for missing den args (matching schema kinds, no default)
        # regardless of whether other den args are found.
        warnedModule = builtins.foldl' (
          mod: k: lib.warn "den: class module requests '${k}' but no ${k} context is available" mod
        ) module missingDenArgNames;
        hasMissingDenArgs = missingDenArgNames != [ ];
      in
      if hasMissingDenArgs then
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
        in
        if remainingArgs == { } then
          {
            module = warnedModule denArgs;
            wrapped = true;
          }
        else
          let
            policy = resolveCollisionPolicy { inherit ctx aspectPolicy globalPolicy; };
            # G(X): the actual module wrapper. Merge order depends on policy.
            # For class-wins args, moduleArgs shadows denArgs (class value used).
            # For den-wins/error args, denArgs shadows moduleArgs (NixOS thunks
            # shadowed without evaluation).
            classWinsNames = builtins.filter (name: policy name == "class-wins") denArgNames;
            classWinsDen = lib.genAttrs classWinsNames (k: denArgs.${k});
            denWinsDen = removeAttrs denArgs classWinsNames;
            wrapper =
              moduleArgs:
              # class-wins args: den first, then moduleArgs shadows
              # den-wins/error args: moduleArgs first, then denArgs shadows
              warnedModule (classWinsDen // moduleArgs // denWinsDen);
            # Validate(X): collision detector. Only advertises module-system
            # args + config. Checks den arg collisions by probing
            # config._module.args rather than advertising den args (which
            # fails when the class module system lacks those keys).
            validatorAdvertisedArgs = remainingArgs // {
              config = true;
            };
            validator = mkCollisionValidator policy denArgNames;
            # Wrapper advertises den args so NixOS passes thunks
            # (shadowed lazily by den values without evaluation).
            advertisedArgs = remainingArgs // lib.genAttrs denArgNames (_: true);
          in
          {
            module = lib.setFunctionArgs wrapper advertisedArgs;
            # Validator emitted separately via emitClasses
            inherit validator validatorAdvertisedArgs;
            wrapped = true;
          };
in
{
  inherit wrapClassModule;
}
