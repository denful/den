# fx-spawn-edges suite — the spawn materializer (assembleSpawnSubtree) now ALSO
# surfaces its constructed delivery-edge set (Task 16). The spawn fold returns
# `{ imports; edges; }`: `imports` is byte-identical to before (consumers read
# only it), and `edges` is the spawn's default-fold merge edge(s) ++ its OWN
# provides edges ++ the RE-APPLIED mergedSpawnRoutes route edges (simple +
# complex), built via the same fold-independent constructors the read-only
# oracle consumes.
#
# Two checks:
#   1. a FOCUSED unit assertion driving assembleSpawnSubtree directly with stub
#      phase primitives + a hand-built mergedSpawnRoutes — asserts the surfaced
#      `.edges` carries the re-applied route edge (the kind the OLD spawn arm,
#      a single rewalk edge, omitted) AND that `.imports` is preserved.
#   2. a topology sanity check — a real spawn-bearing config (a host with a
#      home-manager user) resolves and delivers content, proving the surfacing
#      did not break spawn delivery.
{ denTest, ... }:
let
  mat = den: den.lib.aspects.fx.edges.materialize;

  # Stub phase-1 wrap: the surfaced route/provides edges are built from the spawn's
  # INPUTS (mergedSpawnRoutes / ownProvides) directly, independent of the fold, so a
  # trivial stub returning a well-formed phase-1 accumulator suffices. The
  # accumulator's perScope carries one nixos module at the spawn root, so the
  # default-fold merge edge has content to surface and `.imports` is non-empty.
  # (provides + routes fold through materializeUnified inside assembleSpawnSubtree;
  # ownProvides + mergedSpawnRoutes here deliver no extra nixos content, so the
  # merge over this seed stays the single seeded nixos module.)
  spawnRoot = "spawn=root";
  stubAcc = {
    classImports = {
      nixos = [ { config = { }; } ];
    };
    perScope = {
      ${spawnRoot} = {
        nixos = [ { config = { }; } ];
      };
    };
  };
  wrapPerScope =
    _ctx: _aug: _imports:
    stubAcc;

  # A simple user-schema-style route re-applied at the spawn root (the §B simple
  # route: fromClass→intoClass at a nested path). This is the edge a spawn's
  # mergedSpawnRoutes carries and re-applies; the old spawn drain-fold rendered
  # only a single rewalk edge and omitted it.
  reappliedRoute = {
    sourceScopeId = spawnRoot;
    fromClass = "homeManager";
    intoClass = "nixos";
    path = [
      "home-manager"
      "users"
      "tux"
    ];
  };

  spawnResult =
    den:
    (mat den).assembleSpawnSubtree {
      class = "nixos";
      inherit spawnRoot;
      ctx = { };
      augmented = {
        ${spawnRoot} = { };
      };
      scopeEntityKind = { };
      mergedClassImports = { };
      mergedScopeParent = {
        ${spawnRoot} = "host=igloo";
      };
      mergedScopeIsolated = { };
      ownProvides = { };
      mergedSpawnRoutes = {
        ${spawnRoot} = [ reappliedRoute ];
      };
      allScopeIds = [ spawnRoot ];
      selfRef = null;
      inherit wrapPerScope;
    };
in
{
  flake.tests.fx-spawn-edges = {

    # The surfaced edge set carries the re-applied mergedSpawnRoutes route edge
    # (a homeManager→nixos simple route at the spawn root) — the edge the old
    # spawn arm omitted.
    test-spawn-surfaces-route-edge = denTest (
      { den, lib, ... }:
      let
        r = spawnResult den;
        routeEdges = lib.filter (
          e:
          e.source ? collected
          && e.source.collected.class == "homeManager"
          && e.target.class or null == "nixos"
          &&
            e.path == [
              "home-manager"
              "users"
              "tux"
            ]
        ) r.edges;
      in
      {
        expr = {
          edgesNonEmpty = r.edges != [ ];
          routeEdgeCount = builtins.length routeEdges;
          routeEdgeMode = (builtins.head routeEdges).mode;
        };
        expected = {
          edgesNonEmpty = true;
          routeEdgeCount = 1;
          routeEdgeMode = "nest";
        };
      }
    );

    # The surfaced edge set also carries the spawn's OWN default-fold merge edge
    # (collected(spawnRoot, nixos) → (spawnRoot, nixos), P=[], merge), and
    # `.imports` is preserved (the stub accumulator's one module).
    test-spawn-surfaces-default-fold-and-imports = denTest (
      { den, lib, ... }:
      let
        r = spawnResult den;
        foldEdges = lib.filter (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.source ? collected
          && e.source.collected.class == "nixos"
          && e.target.class or null == "nixos"
        ) r.edges;
      in
      {
        expr = {
          foldEdgeCount = builtins.length foldEdges;
          importsLength = builtins.length r.imports;
        };
        expected = {
          foldEdgeCount = 1;
          importsLength = 1;
        };
      }
    );

    # Topology sanity: a real spawn-bearing config (a host with a home-manager
    # user spawns a home node) resolves and delivers content — the surfacing did
    # not break spawn delivery.
    test-spawn-topology-delivers = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );
  };
}
