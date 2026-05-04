# Effect handler: register-route
# Registers route specs with scope-aware dedup.
{ lib, ... }:
let
  inherit (import ./state-util.nix) scopedAppend;

  registerRouteHandler = {
    "register-route" =
      { param, state }:
      let
        scope = state.currentScope;
        route = param // {
          sourceScopeId = param.sourceScopeId or scope;
        };
        routeKey = "${route.fromClass or "?"}>${route.intoClass or "?"}@${route.sourceScopeId}/${
          lib.concatStringsSep "/" (route.path or [ ])
        }";
        registeredRoutes = (state.registeredRouteKeys or (_: { })) null;
        alreadyRegistered = registeredRoutes ? ${routeKey};
      in
      {
        resume = null;
        state =
          if alreadyRegistered then
            state
          else
            scopedAppend state "scopedRoutes" scope route
            // {
              registeredRouteKeys = _: registeredRoutes // { ${routeKey} = true; };
            };
      };
  };
in
{
  inherit registerRouteHandler;
}
