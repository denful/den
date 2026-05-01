# Handles: emit-forward
# Registers forward spec in pipeline state with captured context.
# Post-processing in pipeline.nix resolves sources and wraps results
# via buildForwardAspect.
{
  lib,
  den,
  ...
}:
let

  mkDirectAspect =
    {
      intoClass,
      staticIntoPath,
      evalConfig,
      freeformMod,
    }:
    sourceModule:
    if evalConfig then
      let
        evaluated = lib.evalModules {
          modules = [
            freeformMod
            sourceModule
          ];
        };
      in
      {
        ${intoClass} = lib.setAttrByPath staticIntoPath (
          builtins.removeAttrs evaluated.config [ "_module" ]
        );
      }
    else
      {
        ${intoClass} = lib.setAttrByPath staticIntoPath (_: {
          imports = [ sourceModule ];
        });
        meta.contextDependent = true;
      };

  mkAdapterAspect =
    {
      intoClass,
      adapterKey,
      guardFn,
      guardArgs,
      intoPathArgs,
      intoPathFn,
      adaptArgsFn,
      adaptArgv,
      adapterMods,
      freeformMod,
    }:
    sourceModule: {
      meta.contextDependent = true;
      includes = [
        (mkDirectAspect {
          inherit intoClass freeformMod;
          staticIntoPath = [
            "den"
            "fwd"
            adapterKey
          ];
          evalConfig = false;
        } sourceModule)
      ];
      ${intoClass} = {
        __functionArgs = guardArgs // intoPathArgs // adaptArgv;
        __functor = _: args: {
          options.den.fwd.${adapterKey} = lib.mkOption {
            defaultText = lib.literalExpression "{ }";
            default = { };
            type = lib.types.submoduleWith {
              specialArgs = adaptArgsFn args;
              modules = adapterMods;
            };
          };
          config = guardFn args (lib.setAttrByPath (intoPathFn args) args.config.den.fwd.${adapterKey});
        };
      };
    };

  guardTree =
    guard: outerArgs: node:
    if builtins.isAttrs node && node ? imports then
      { imports = map (guardTree guard outerArgs) node.imports; }
    else
      _modArgs: {
        config = guard (if lib.isFunction node then node outerArgs else node);
      };

  evalImport =
    {
      adapterMods,
      sourceModule,
      extraArgsFor,
      guardFn,
    }:
    args:
    let
      extraArgs = extraArgsFor args;
      specialArgs =
        builtins.removeAttrs args [
          "config"
          "options"
          "lib"
        ]
        // extraArgs;
      evaluated = lib.evalModules {
        inherit specialArgs;
        modules = adapterMods ++ [
          sourceModule
        ];
      };
    in
    guardFn args evaluated.config;

  mkTopLevelAdapterAspect =
    {
      intoClass,
      guardFn,
      guardArgs,
      extraArgsFor,
      canDirectImport,
      adapterMods,
    }:
    sourceModule: {
      meta.contextDependent = true;
      ${intoClass} = {
        __functionArgs = guardArgs;
        __functor =
          _: args:
          let
            fullArgs = args // extraArgsFor args;
          in
          if canDirectImport then
            {
              imports = [ (guardTree (guardFn args) fullArgs sourceModule) ];
            }
          else
            evalImport {
              inherit
                adapterMods
                sourceModule
                extraArgsFor
                guardFn
                ;
            } args;
      };
    };

  # Build the same aspect shape the old forwardItem produced,
  # but with sourceModule resolved using the parent pipeline's context.
  buildForwardAspect =
    spec: sourceModule:
    let
      base = {
        includes = [ ];
        meta = { };
      };
      body =
        if spec.needsTopLevelAdapter then
          mkTopLevelAdapterAspect {
            inherit (spec)
              intoClass
              guardFn
              guardArgs
              extraArgsFor
              canDirectImport
              adapterMods
              ;
          } sourceModule
        else if spec.needsAdapter then
          mkAdapterAspect {
            inherit (spec)
              intoClass
              adapterKey
              guardFn
              guardArgs
              intoPathArgs
              intoPathFn
              adaptArgsFn
              adaptArgv
              adapterMods
              freeformMod
              ;
          } sourceModule
        else
          mkDirectAspect {
            inherit (spec)
              intoClass
              staticIntoPath
              evalConfig
              freeformMod
              ;
          } sourceModule;
    in
    base // body;

  # Register forward spec in state with captured context for post-processing.
  # Post-processing in pipeline.nix runs sub-pipelines and wraps results.
  forwardHandler = {
    "emit-forward" =
      { param, state }:
      let
        spec = param;
        scope = state.currentScope;

        # Tier 1 classification: simple forwards with source modules already
        # in the current pipeline's scopedClassImports can become routes.
        # Requirements:
        # - No adapter, no guard, static path, no evalConfig
        # - Source aspect has no own context (__scopeHandlers — external
        #   entities like resolveEntity carry these)
        # - Source class already collected in current scope (excludes
        #   synthetic source aspects whose modules aren't in the pipeline)
        isSimpleSpec = spec.canDirectImport && !spec.needsAdapter && !(spec.evalConfig or false);
        sourceScopeHandlers = spec.sourceAspect.__scopeHandlers or { };
        sourceIsLocal = sourceScopeHandlers == { };
        scopeClasses = (state.scopedClassImports null).${scope} or { };
        sourceAlreadyCollected = scopeClasses ? ${spec.fromClass};
        isTier1 = isSimpleSpec && sourceIsLocal && sourceAlreadyCollected;

        # Tier 1: register as a route (source modules already in scopedClassImports).
        tier1Result = {
          resume = null;
          state = state // {
            scopedRoutes =
              _:
              let
                all = state.scopedRoutes null;
                route = {
                  inherit (spec) fromClass intoClass;
                  path = spec.staticIntoPath;
                  guard = null;
                  adaptArgs = null;
                  sourceScopeId = scope;
                };
              in
              all
              // {
                ${scope} = (all.${scope} or [ ]) ++ [ route ];
              };
          };
        };

        # Tier 2: register as route with full adapter fields.
        # Forward sub-pipelines eliminated — source modules are resolved
        # in-pipeline via dispatch-policies. Route application uses the
        # adapter fields for submodule wrapping when present.
        sourceScopeCtx =
          if sourceScopeHandlers != { } then
            den.lib.aspects.fx.aspect.ctxFromHandlers sourceScopeHandlers
          else if scope == null then
            { }
          else
            (state.scopeContexts null).${scope} or { };
        sourceScopeId = den.lib.aspects.fx.pipeline.mkScopeId sourceScopeCtx;
        tier2Result = {
          resume = null;
          state = state // {
            scopedRoutes =
              _:
              let
                all = state.scopedRoutes null;
                route = {
                  inherit (spec) fromClass intoClass;
                  path = spec.staticIntoPath;
                  guard = spec.guardFn or null;
                  adaptArgs = spec.adaptArgsFn or null;
                  sourceScopeId = if sourceAlreadyCollected then scope else sourceScopeId;
                  # Adapter fields for Tier 2 forwards.
                  adapterModule = if spec.adapterMods or [ ] != [ ] then { imports = spec.adapterMods; } else null;
                  intoPathFn = spec.intoPathFn or null;
                  freeformMod = spec.freeformMod or null;
                  adapterKey = spec.adapterKey or null;
                  adaptArgv = spec.adaptArgv or { };
                  guardArgs = spec.guardArgs or { };
                  intoPathArgs = spec.intoPathArgs or { };
                  extraArgsFor = spec.extraArgsFor or null;
                };
              in
              all
              // {
                ${scope} = (all.${scope} or [ ]) ++ [ route ];
              };
          };
        };
      in
      if isTier1 then tier1Result else tier2Result;
  };

in
{
  inherit forwardHandler buildForwardAspect;
}
