# Effect handler: emit-class
# Collects class modules into scope-partitioned buckets with dedup.
{ den, ... }:
let
  classCollectorHandler = {
    "emit-class" =
      { param, state }:
      let
        nodeIdentity = param.identity or "<anon>";
        isRawEntry = param.__rawEntry or false;
        baseIdentity =
          if param.isContextDependent or false then
            nodeIdentity
          else
            den.lib.aspects.fx.identity.stripCtxSuffix nodeIdentity;
        loc = "${param.class}@${baseIdentity}";
        mod =
          if isRawEntry then
            param // { __loc = loc; }
          else if den.lib.aspects.fx.identity.isAnonIdentity nodeIdentity then
            den.lib.setDefaultModuleLocation loc param.module
          else
            {
              key = loc;
              _file = loc;
              imports = [ param.module ];
            };
        scope = state.currentScope;
        emittedLocs = (state.scopedEmittedLocs or (_: { })) null;
        scopeLocs = emittedLocs.${scope} or { };
        alreadyEmitted = scopeLocs ? ${loc};
      in
      {
        resume = null;
        state =
          if alreadyEmitted then
            state
          else
            let
              allImports = state.scopedClassImports null;
              scopeImportData = allImports.${scope} or { };
              updatedImports = allImports // {
                ${scope} = scopeImportData // {
                  ${param.class} = (scopeImportData.${param.class} or [ ]) ++ [ mod ];
                };
              };
            in
            state
            // {
              scopedClassImports = _: updatedImports;
              scopedEmittedLocs =
                _:
                emittedLocs
                // {
                  ${scope} = scopeLocs // {
                    ${loc} = true;
                  };
                };
            };
      };
  };
in
{
  inherit classCollectorHandler;
}
