# Effect handler: register-route
# Registers route specs with scope-aware dedup.
{ lib, ... }:
let
  inherit (import ./state-util.nix) scopedAppend;

  # Canonical route dedup identity. Shared with the spawn-node merge of
  # parent-pipeline routes — both sides must key routes identically or
  # dedup silently diverges.
  routeKey =
    fallbackScope: r:
    "${r.fromClass or "?"}>${r.intoClass or "?"}@${r.sourceScopeId or fallbackScope}/${
      lib.concatStringsSep "/" (r.path or [ ])
    }"
    # mutual-provider registers one route per provider at a scope (#694).
    + lib.optionalString ((r.__fromProvenance or null) != null) "#${r.__fromProvenance}";

  registerRouteHandler = {
    "register-route" =
      { param, state }:
      let
        scope = state.currentScope;
        route = param // {
          sourceScopeId = param.sourceScopeId or scope;
        };
        key = routeKey scope route;
        registeredRoutes = (state.registeredRouteKeys or (_: { })) null;
        alreadyRegistered = registeredRoutes ? ${key};
      in
      {
        resume = null;
        state =
          if alreadyRegistered then
            state
          else
            scopedAppend state "scopedRoutes" scope route
            // {
              registeredRouteKeys = _: registeredRoutes // { ${key} = true; };
            };
      };
  };
in
{
  inherit registerRouteHandler routeKey;
}
