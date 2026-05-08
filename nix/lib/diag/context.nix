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
      ctx ? { },
      direction ? "LR",
    }:
    let
      captured = capture.captureWithPathsWith { inherit classes root ctx; };

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
      ctx = { inherit host; };
      root = den.lib.resolveEntity "host" ctx;
    in
    context {
      inherit root direction ctx;
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
      ctx = { inherit host user; };
      root = den.lib.resolveEntity "user" ctx;
    in
    context {
      inherit root direction ctx;
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
      ctx = { inherit home; };
      root = den.lib.resolveEntity "home" ctx;
    in
    context {
      inherit root direction ctx;
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
