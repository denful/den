{
  lib,
  den,
  ...
}:
let
  # __ctxId differentiates fan-out contexts so the same target aspect
  # with different context values produces distinct NixOS module dedup keys.
  aspectPath =
    a:
    (a.meta.provider or [ ]) ++ [ (a.name or "<anon>") ] ++ lib.optional (a ? __ctxId) "{${a.__ctxId}}";

  pathKey = path: lib.concatStringsSep "/" path;

  toPathSet =
    paths:
    builtins.listToAttrs (
      builtins.map (p: {
        name = pathKey p;
        value = true;
      }) paths
    );

  tombstone = resolved: extra: {
    name = "~${resolved.name or "<anon>"}";
    meta =
      (resolved.meta or { })
      // {
        excluded = true;
        originalName = resolved.name or "<anon>";
      }
      // extra;
    includes = [ ];
  };

  collectPathsHandler = {
    "resolve-complete" =
      { param, state }:
      let
        isExcluded = param.meta.excluded or false;
        path = aspectPath param;
        key = pathKey path;
        # Also store base path (without ctxId) so hasAspect can match
        # without needing to know the specific context instance.
        basePath = (param.meta.provider or [ ]) ++ [ (param.name or "<anon>") ];
        baseKey = pathKey basePath;
      in
      {
        resume = param;
        state =
          state
          // lib.optionalAttrs (!isExcluded) {
            pathSet =
              _:
              (state.pathSet or (_: { })) null
              // {
                ${key} = true;
              }
              // lib.optionalAttrs (baseKey != key) {
                ${baseKey} = true;
              };
          };
      };
  };

  pathSetHandler = {
    "get-path-set" =
      { param, state }:
      {
        resume = (state.pathSet or (_: { })) null;
        inherit state;
      };
  };

in
{
  inherit
    aspectPath
    pathKey
    toPathSet
    tombstone
    collectPathsHandler
    pathSetHandler
    ;
}
