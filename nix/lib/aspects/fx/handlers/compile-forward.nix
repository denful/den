# Effect handler: compile-forward
# Extracts forward spec from aspect payload, classifies tier, registers route.
# Resumes [] — forwards bypass dedup + constraints.
{ ... }:
let
  inherit (import ./state-util.nix) scopedAppend;
in
{
  compileForwardHandler = {
    "compile-forward" =
      { param, state }:
      let
        spec = param.aspect.meta.__forward;
        scope = state.currentScope;

        # Tier 1 classification: simple forwards with source modules already
        # in the current pipeline's scopedClassImports can become routes.
        isSimpleSpec = spec.canDirectImport && !spec.needsAdapter && !(spec.evalConfig or false);
        sourceScopeHandlers = spec.sourceAspect.__scopeHandlers or { };
        sourceIsLocal = sourceScopeHandlers == { };
        scopeClasses = (state.scopedClassImports null).${scope} or { };
        sourceAlreadyCollected = scopeClasses ? ${spec.fromClass};
        isTier1 = isSimpleSpec && sourceIsLocal && sourceAlreadyCollected;

        # Tier 1: simple route shape (backward compatible).
        simpleRoute = {
          inherit (spec) fromClass intoClass;
          path = spec.staticIntoPath;
          guard = null;
          adaptArgs = null;
          sourceScopeId = scope;
        };

        # Complex: full forward spec as route with __complexForward marker.
        complexRoute = spec // {
          sourceScopeId = scope;
          __complexForward = true;
        };

        route = if isTier1 then simpleRoute else complexRoute;
      in
      {
        resume = [ ];
        state = scopedAppend state "scopedRoutes" scope route;
      };
  };
}
