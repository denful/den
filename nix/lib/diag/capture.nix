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
      extraHandlers ? { },
    }:
    let
      rawPerClass = lib.genAttrs classes (
        class:
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
          }) (fxLib.trace.tracingHandler class // extraHandlers);
          state = fxLib.pipeline.defaultState // {
            entries = [ ];
            ctxTrace = [ ];
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
in
{
  inherit
    capture
    captureAll
    captureWithPaths
    captureWithPathsWith
    ;
}
