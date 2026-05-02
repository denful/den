# Handles: resolve-parametric
# Probes handlers for required args, resolves or defers.
{
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
in
{
  resolveParametricHandler = {
    "resolve-parametric" =
      { param, state }:
      let
        child = param;
        childArgs = child.__args or { };
        childScopeHandlers = child.__scopeHandlers or { };
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
            fx.bind (aspectToEffect child) (resolved: fx.pure [ resolved ])
          else
            let
              stub = {
                name = child.name or "<anon>";
                meta = (child.meta or { }) // {
                  deferred = true;
                };
                includes = [ ];
              };
            in
            fx.bind (fx.send "resolve-complete" stub) (
              _:
              fx.bind (fx.send "defer-include" {
                inherit child requiredKeys;
                requiredArgs = keysToProbe;
              }) (_: fx.pure [ ])
            )
        );
        inherit state;
      };
  };
}
