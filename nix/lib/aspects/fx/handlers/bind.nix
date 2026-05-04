# Handles: bind
# Probes scope handlers for required args, calls compileFn or defers.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
in
{
  bindHandler = {
    "bind" =
      { param, state }:
      let
        inherit (param) aspect compileFn;
        childArgs = aspect.__args or { };
        childScopeHandlers = aspect.__scopeHandlers or { };
        requiredKeys = builtins.filter (k: !childArgs.${k}) (builtins.attrNames childArgs);
        keysToProbe = builtins.filter (k: !(childScopeHandlers ? ${k})) requiredKeys;
        probeArgs =
          keys:
          if keys == [ ] then
            fx.pure true
          else
            let
              key = builtins.head keys;
              rest = builtins.tail keys;
            in
            fx.bind (fx.effects.hasHandler key) (
              isAvailable: if isAvailable then probeArgs rest else fx.pure false
            );
      in
      {
        resume = fx.bind (probeArgs keysToProbe) (
          allAvailable:
          if allAvailable then
            fx.bind (compileFn aspect) (result: fx.pure { value = result; })
          else
            fx.bind (fx.send "defer" {
              child = aspect;
              inherit requiredKeys;
              requiredArgs = keysToProbe;
            }) (_: fx.pure { deferred = true; })
        );
        inherit state;
      };
  };
}
