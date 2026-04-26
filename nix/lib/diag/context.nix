# Entity-agnostic context constructors.
#
# Build graph IR from any resolved stage root (host, user, home,
# or custom entity kind). Callers resolve via `den.lib.resolveEntity`
# and pass the result here, or use convenience wrappers below.
{
  den,
  lib,
  capture,
  graphLib,
  ...
}:
let
  # Entity-agnostic core — build graph IR from a resolved root.
  context =
    {
      root,
      name,
      classes,
      direction ? "LR",
    }:
    let
      captured = capture.captureWithPaths classes root;

      graph = graphLib.buildGraph {
        entries = captured.entries;
        rootName = name;
        ctxTrace = captured.ctxTrace;
        inherit direction;
      };
      pathSets = captured.pathsByClass;
    in
    graph
    // {
      rootAspect = root;
      inherit pathSets classes;
    };

  # Host convenience wrapper.
  hostContext =
    {
      host,
      classes ? null,
      direction ? "LR",
    }:
    let
      userClasses = lib.unique (lib.concatMap (u: u.classes or [ ]) (lib.attrValues (host.users or { })));
      actualClasses =
        if classes != null then
          classes
        else
          lib.unique (
            [
              "nixos"
              "homeManager"
              "user"
            ]
            ++ userClasses
          );
      root = den.lib.resolveEntity "host" { inherit host; };
    in
    context {
      inherit root direction;
      name = host.name;
      classes = actualClasses;
    };

  # User convenience wrapper.
  userContext =
    {
      host,
      user,
      classes ? null,
      direction ? "LR",
    }:
    let
      actualClasses =
        if classes != null then
          classes
        else
          lib.unique (
            [
              "homeManager"
              "user"
            ]
            ++ (user.classes or [ "homeManager" ])
          );
      root = den.lib.resolveEntity "user" { inherit host user; };
    in
    context {
      inherit root direction;
      name = user.name;
      classes = actualClasses;
    };

  # Home convenience wrapper.
  homeContext =
    {
      home,
      classes ? null,
      direction ? "LR",
    }:
    let
      actualClasses =
        if classes != null then
          classes
        else
          lib.unique ([ "homeManager" ] ++ (home.classes or [ "homeManager" ]));
      root = den.lib.resolveEntity "home" { inherit home; };
    in
    context {
      inherit root direction;
      name = home.name;
      classes = actualClasses;
    };

  # Thin wrapper returning a plain graph (no auxiliary fields).
  graphOfHost =
    args:
    removeAttrs (hostContext args) [
      "rootAspect"
      "pathSets"
      "classes"
    ];
in
{
  inherit
    context
    hostContext
    userContext
    homeContext
    graphOfHost
    ;
}
