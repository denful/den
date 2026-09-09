# Handles: defer
# Emits resolve-complete stub, queues deferred include in scoped state.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) argClass;
  inherit (import ./state-util.nix) scopedAppend;
  schema = den.schema or { };
  isEntityKind = argClass.isEntityKind schema;
in
{
  deferHandler = {
    "defer" =
      { param, state }:
      let
        inherit (param) child requiredKeys requiredArgs;
        # Entity-kind args never reach defer: bind classifies every entity arg
        # (ctx/fan-out/inert) synchronously. A leaked entity arg here is a
        # resolver bug — fail loud rather than silently dangle.
        entityArgs = builtins.filter isEntityKind requiredArgs;
        guard =
          if entityArgs == [ ] then
            null
          else
            throw "den: entity-kind arg '${builtins.head entityArgs}' reached defer for aspect '${child.name or "<anon>"}' — bind should have classified it (fan-out/inert); this is a resolver bug";
        # Bookkeeping only — deliberately NOT a rebuild of `child`. The child
        # is queued intact below and resolves in full when the drain fires;
        # this record exists so the deferred node still registers an identity,
        # and every resolve-complete consumer (identity.collectPathsHandler,
        # trace.nix) reads name/meta and nothing else. `includes = [ ]` states
        # that this marker carries no children of its own — it is a reset, not
        # a dropped carry-forward, and adding structural state here would only
        # duplicate what the drained `child` emits later.
        stub = {
          name = child.name or "<anon>";
          meta = (child.meta or { }) // {
            deferred = true;
          };
          includes = [ ];
        };
      in
      builtins.seq guard {
        resume = fx.bind (fx.send "resolve-complete" stub) (_: fx.pure [ ]);
        state = scopedAppend state "scopedDeferredIncludes" state.currentScope {
          inherit child requiredKeys requiredArgs;
          hasPipeArgs = param.hasPipeArgs or false;
        };
      };
  };
}
