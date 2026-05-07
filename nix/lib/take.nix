# DEPRECATED: scheduled for removal after first stable release post-fx-pipeline merge.
# Migration: use den.lib.canTake instead.
# Deprecated context-level guards.
# Under handler-based resolution, bind.fn resolves args from handlers.
# take.exactly uses optional-arg detection to gate on context level.
# take.atLeast and take.upTo are identity (the pipeline's deferral
# provides atLeast semantics naturally).
{ lib, ... }:
let
  take.unused = _unused: used: used;

  take.exactly =
    fn:
    let
      args = lib.functionArgs fn;
      requiredKeys = builtins.filter (k: !args.${k}) (builtins.attrNames args);
    in
    if requiredKeys == [ ] then
      fn
    else
      lib.warn "den.lib.take.exactly is deprecated — bind.fn resolves args from handlers" {
        __fn =
          resolvedArgs:
          let
            # __scopeKeys is injected by the compile-parametric handler when meta.exactMatch is set.
            # It contains all scope handler keys so we can detect extra context beyond
            # the function's declared args.
            # Filter out `class` — it's an internal routing key added by push-scope,
            # not a user-facing context arg that should affect exact matching.
            scopeKeys = builtins.filter (k: k != "class") (resolvedArgs.__scopeKeys or [ ]);
            cleanArgs = builtins.removeAttrs resolvedArgs [ "__scopeKeys" ];
            # Check 1: all required keys must be resolved
            hasMissing = builtins.any (k: !(cleanArgs ? ${k})) requiredKeys;
            # Check 2: no extra context beyond declared args
            hasExtras = builtins.any (k: !(args ? ${k})) scopeKeys;
          in
          if hasMissing || hasExtras then { } else fn (lib.intersectAttrs args cleanArgs);
        # All args are optional so the wrapper is never deferred.
        # Missing args are detected in __fn and produce {} (no-op).
        __args = lib.mapAttrs (_: _: true) args;
        meta.exactMatch = true;
      };

  take.atLeast =
    fn: lib.warn "den.lib.take.atLeast is deprecated — bind.fn resolves args from handlers" fn;

  take.upTo = fn: lib.warn "den.lib.take.upTo is deprecated — bind.fn resolves args from handlers" fn;

  # Deprecated: custom predicate form.
  take.__functor =
    _: _canTakePred: _argAdapter: fn:
    lib.warn "den.lib.take custom predicate is deprecated — use plain parametric functions" fn;
in
take
