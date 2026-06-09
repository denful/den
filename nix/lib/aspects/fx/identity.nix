{
  lib,
  den,
  ...
}:
let
  aspectPath =
    a:
    (a.meta.provider or [ ]) ++ [ (a.name or "<anon>") ] ++ lib.optional (a ? __ctxId) "{${a.__ctxId}}";

  pathKey = path: lib.concatStringsSep "/" path;

  # Composed: aspectPath → pathKey in one call.
  key = a: pathKey (aspectPath a);

  # True when an identity string refers to an anonymous/unresolved node.
  isAnonIdentity =
    id:
    !(den.lib.aspects.isMeaningfulName id) || lib.hasPrefix "<root>/" id || lib.hasInfix "/<anon>:" id;

  # Strip the {ctxId} suffix from an identity, yielding the base identity.
  stripCtxSuffix = id: lib.head (lib.splitString "/{" id);

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
            pathSetByScope =
              _:
              let
                prev = (state.pathSetByScope or (_: { })) null;
                scope = state.currentScope;
                scopeSet = prev.${scope} or { };
              in
              prev
              // {
                ${scope} = scopeSet // {
                  ${baseKey} = true;
                };
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
    key
    isAnonIdentity
    stripCtxSuffix
    toPathSet
    tombstone
    collectPathsHandler
    pathSetHandler
    ;
}
