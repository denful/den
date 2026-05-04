# Route module delivery — move modules between entity scopes/classes.
{
  lib,
  den,
  ...
}:
let
  inherit (import ./wrap.nix { inherit lib den; }) wrapRouteModules collectClassMods;
  inherit
    (import ./apply.nix {
      inherit
        lib
        den
        wrapRouteModules
        collectClassMods
        ;
    })
    applyRoutes
    ;
in
{
  inherit wrapRouteModules applyRoutes;
}
