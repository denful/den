# Handles: resolve-aspect
# Static resolution via aspectToEffect.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
in
{
  resolveAspectHandler = {
    "resolve-aspect" =
      { param, state }:
      {
        resume = fx.bind (aspectToEffect param) (resolved: fx.pure [ resolved ]);
        inherit state;
      };
  };
}
