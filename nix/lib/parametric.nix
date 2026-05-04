# DEPRECATED: scheduled for removal after first stable release post-fx-pipeline merge.
# Migration: use parametric aspect includes ({ host, user }: { ... }) directly.
{ lib, den, ... }:
let
  warn = msg: v: lib.warn "den.lib.parametric: ${msg}" v;

  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # fixedTo pins context values via __scopeHandlers. The fx pipeline's
  # scope.provide installs these for parametric children via bind.fn.
  # Returns a parametric wrapper so it survives providerType submodule merge.
  mkFixedTo = ctx: aspect: {
    __fn = _: aspect;
    __args = lib.mapAttrs (_: _: true) ctx;
    __scopeHandlers = (aspect.__scopeHandlers or { }) // constantHandler ctx;
    name = aspect.name or "<fixedTo>";
    meta = aspect.meta or { };
  };

  parametric.fixedTo.__functor =
    _: ctx: aspect:
    warn "fixedTo is deprecated — the fx pipeline provides context via effects" (mkFixedTo ctx aspect);
  parametric.fixedTo.exactly =
    ctx: aspect: warn "fixedTo.exactly is deprecated" (mkFixedTo ctx aspect);
  parametric.fixedTo.atLeast =
    ctx: aspect: warn "fixedTo.atLeast is deprecated" (mkFixedTo ctx aspect);
  parametric.fixedTo.upTo = ctx: aspect: warn "fixedTo.upTo is deprecated" (mkFixedTo ctx aspect);

  parametric.atLeast = aspect: warn "atLeast is deprecated — use plain attrsets" aspect;
  parametric.exactly = aspect: warn "exactly is deprecated — use plain attrsets" aspect;
  # expands merges extra context attrs into __scopeHandlers for parametric children.
  # Returns a parametric wrapper so it survives providerType submodule merge
  # (plain attrsets with __scopeHandlers would have it captured by freeform).
  parametric.expands =
    attrs: aspect:
    warn "expands is deprecated" {
      __fn = _: aspect;
      __args = lib.mapAttrs (_: _: true) attrs;
      __scopeHandlers = (aspect.__scopeHandlers or { }) // constantHandler attrs;
      name = aspect.name or "<expands>";
      meta = aspect.meta or { };
    };

  parametric.__functor = _: parametric.atLeast;
in
parametric
