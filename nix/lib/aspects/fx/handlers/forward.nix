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
        # Capture parent entity context at handler time for post-processing.
        # Sources with explicit context (__scopeHandlers) keep theirs;
        # sources without context inherit parent entities.
        scope = state.currentScope;
        parentCtx = if scope == null then { } else (state.scopeContexts null).${scope} or { };
        entityCtx = lib.filterAttrs (_: builtins.isAttrs) parentCtx;
        sourceScopeHandlers = spec.sourceAspect.__scopeHandlers or { };
        sourceCtx = den.lib.aspects.fx.aspect.ctxFromHandlers sourceScopeHandlers;
        hasOwnContext = sourceScopeHandlers != { };
        resolveCtx = if hasOwnContext then sourceCtx else entityCtx;
        parentAspectPolicies = state.aspectPolicies or (_: { });
        enrichedSpec = spec // {
          __resolveCtx = resolveCtx;
          __aspectPolicies = parentAspectPolicies;
        };
      in
      {
        resume = null;
        state = state // {
          forwardSpecs = x: (state.forwardSpecs x) ++ [ enrichedSpec ];
          scopedForwardSpecs =
            x:
            let
              all = state.scopedForwardSpecs x;
              scope = state.currentScope;
            in
            all
            // {
              ${scope} = (all.${scope} or [ ]) ++ [ enrichedSpec ];
            };
        };
      };
  };

in
{
  inherit forwardHandler buildForwardAspect;
}
