# Handles: emit-forward
# Resolves forwarded source in a sub-pipeline (fxFullResolve) for state
# isolation, wraps the result in an adapter aspect, and re-emits as an
# include. Provide-to emissions from the sub-pipeline are spliced into
# the parent's provideTo thunk chain for phase 2 distribution.
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects) normalizeRoot;

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

  forwardHandler = {
    "emit-forward" =
      { param, state }:
      let
        spec = param;
        normalizedSource = normalizeRoot spec.sourceAspect;

        # Propagate parent entity context (host, user, etc.) to the
        # sub-pipeline so parametric includes can resolve. Sources with
        # explicit context (fromCtx / __scopeHandlers) keep theirs;
        # sources without context inherit parent entities (attrset
        # values only -- scalars and functions like class/aspect-chain
        # are pipeline-internal and excluded).
        parentCtx = (state.currentCtx or (_: { })) null;
        entityCtx = lib.filterAttrs (_: builtins.isAttrs) parentCtx;
        sourceCtx = spec.sourceAspect.__ctx or { };
        hasOwnContext = sourceCtx != { } || (spec.sourceAspect.__scopeHandlers or { }) != { };
        resolveCtx = if hasOwnContext then sourceCtx else entityCtx;

        sourceResult = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = spec.fromClass;
          self = normalizedSource;
          ctx = resolveCtx;
        };

        rawSourceModule = {
          imports = sourceResult.state.imports null;
        };
        sourceModule = spec.mapModule rawSourceModule;

        forwardAspect = buildForwardAspect spec sourceModule;

        # Propagate provide-to from sub-pipeline to parent state directly.
        # We can't iterate the list (map/length/== forces the ++ chain
        # which forces param attrsets containing fixpoint closures).
        # Instead, append the sub-pipeline's thunk to parent's thunk chain
        # so the ++ is deferred until distribution time.
        subProvideToThunk = sourceResult.state.provideTo or (_: [ ]);
      in
      {
        resume = fx.send "emit-include" {
          child = forwardAspect;
          idx = null;
        };
        # Splice sub-pipeline's provideTo thunk into parent's thunk chain.
        # At distribution time: (state.provideTo null) evaluates both.
        state = state // {
          provideTo = _: ((state.provideTo or (_: [ ])) null) ++ (subProvideToThunk null);
        };
      };
  };

in
{
  inherit forwardHandler;
}
