# Handles: defer
# Emits resolve-complete stub, queues deferred include in scoped state.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (import ./state-util.nix) scopedAppend;
in
{
  deferHandler = {
    "defer" =
      { param, state }:
      let
        inherit (param) child requiredKeys requiredArgs;
        stub = {
          name = child.name or "<anon>";
          meta = (child.meta or { }) // {
            deferred = true;
          };
          includes = [ ];
        };
      in
      {
        resume = fx.bind (fx.send "resolve-complete" stub) (_: fx.pure [ ]);
        state = scopedAppend state "scopedDeferredIncludes" state.currentScope {
          inherit child requiredKeys requiredArgs;
          hasPipeArgs = param.hasPipeArgs or false;
        };
      };
  };
}
