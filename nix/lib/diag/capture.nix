# Trace capture: collect structured trace entries from resolved aspects
# via the fx pipeline's tracingHandler.
#
# Usage:
#   entries = diag.capture "nixos" rootAspect;
#   entries = diag.captureAll [ "nixos" "homeManager" ] rootAspect;
#   { entries, pathsByClass, ctxTrace } = diag.captureWithPaths classes rootAspect;
{
  den,
  lib,
  ...
}:
let
  nxFx = den.lib.fx;
  fxLib = den.lib.aspects.fx;

  captureRaw =
    class: root:
    let
      comp = nxFx.send "resolve" {
        aspect = root;
        identity = fxLib.identity.key root;
        ctx = { };
      };
    in
    nxFx.handle {
      handlers = fxLib.pipeline.composeHandlers (fxLib.pipeline.defaultHandlers {
        inherit class;
        ctx = { };
      }) (fxLib.trace.tracingHandler class);
      state = fxLib.pipeline.defaultState // {
        entries = [ ];
        ctxTrace = [ ];
      };
    } comp;

  capture = class: root: (captureRaw class root).state.entries;

  captureAll = classes: root: lib.concatMap (class: capture class root) classes;

  captureWithPathsWith =
    {
      classes,
      root,
      ctx ? { },
      extraHandlers ? { },
    }:
    let
      rootScopeId = fxLib.pipeline.mkScopeId ctx;
      rawPerClass = lib.genAttrs classes (
        class:
        let
          comp = nxFx.send "resolve" {
            aspect = root;
            identity = fxLib.identity.key root;
            inherit ctx;
          };
        in
        nxFx.handle {
          handlers = fxLib.pipeline.composeHandlers (fxLib.pipeline.defaultHandlers {
            inherit class ctx;
          }) (fxLib.trace.tracingHandler class // extraHandlers);
          state = fxLib.pipeline.defaultState // {
            entries = [ ];
            ctxTrace = [ ];
            inherit rootScopeId;
            currentScope = rootScopeId;
            scopeContexts = _: {
              ${rootScopeId} = ctx;
            };
          };
        } comp
      );
    in
    {
      entries = lib.concatMap (c: rawPerClass.${c}.state.entries) classes;
      # Unwrap thunked pathSet — pipeline wraps growing state fields as
      # (_: value) to survive deepSeq. Apply null to unwrap.
      pathsByClass = lib.mapAttrs (_: r: (r.state.pathSet or (_: { })) null) rawPerClass;
      ctxTrace =
        let
          first = rawPerClass.${lib.head classes};
        in
        first.state.ctxTrace or [ ];
    };

  captureWithPaths = classes: root: captureWithPathsWith { inherit classes root; };

  # Fleet-level capture: run the full pipeline from the flake root with
  # trace handlers. Returns trace entries AND post-pipeline state for
  # pipe flow analysis (scopedPipeEffects, scopedClassImports, scopeParent,
  # scopeContexts, scopeEntityKind).
  #
  # Unlike per-host capture, this walks the ENTIRE flake scope tree:
  # flake → fleet → environment → host → user.
  captureFleet =
    {
      class ? "nixos",
      extraHandlers ? { },
    }:
    let
      flakeRoot = den.lib.resolveEntity "flake" { };
      comp = nxFx.send "resolve" {
        aspect = flakeRoot;
        identity = fxLib.identity.key flakeRoot;
        ctx = { };
      };
      result = nxFx.handle {
        handlers = fxLib.pipeline.composeHandlers (fxLib.pipeline.defaultHandlers {
          inherit class;
          ctx = { };
        }) (fxLib.trace.tracingHandler class // extraHandlers);
        state = fxLib.pipeline.defaultState // {
          entries = [ ];
          ctxTrace = [ ];
        };
      } comp;
      st = result.state;
    in
    {
      entries = st.entries or [ ];
      ctxTrace = st.ctxTrace or [ ];
      # Post-pipeline scope data for pipe flow analysis.
      scopeParent = (st.scopeParent or (_: { })) null;
      scopeContexts = (st.scopeContexts or (_: { })) null;
      scopeEntityKind = (st.scopeEntityKind or (_: { })) null;
      scopedPipeEffects = (st.scopedPipeEffects or (_: { })) null;
      scopedClassImports = (st.scopedClassImports or (_: { })) null;
      # Phase 2: pipe production/consumption from trace handlers.
      pipeProducers = st.pipeProducers or [ ];
      pipeConsumers = st.pipeConsumers or [ ];
    };
in
{
  inherit
    capture
    captureAll
    captureWithPaths
    captureWithPathsWith
    captureFleet
    ;
}
