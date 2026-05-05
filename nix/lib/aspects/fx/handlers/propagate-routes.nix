# Effect handler: propagate-routes
# Copies relevant root-scope complex routes to a child scope.
{ lib, ... }:
let
  inherit (import ./state-util.nix) scopedAppendMany;

  propagateRoutesHandler = {
    "propagate-routes" =
      { param, state }:
      let
        inherit (param) scopeId;
        rootSid = state.rootScopeId;
        rootRoutes = (state.scopedRoutes null).${rootSid} or [ ];
        childClasses = (state.scopedClassImports null).${scopeId} or { };
        complexRootRoutes = builtins.filter (r: r.__complexForward or false) rootRoutes;
        childRoutes = map (r: r // { sourceScopeId = scopeId; }) (
          builtins.filter (r: childClasses ? ${r.fromClass}) complexRootRoutes
        );
      in
      if childRoutes == [ ] then
        {
          resume = null;
          inherit state;
        }
      else
        {
          resume = null;
          state = scopedAppendMany state "scopedRoutes" scopeId childRoutes;
        };
  };
in
{
  inherit propagateRoutesHandler;
}
