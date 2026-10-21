# fx-instantiate-edges suite — the per-host re-walk's surfaced edge set
# (nix/lib/aspects/fx/edges/instantiate-edges.nix mkInstantiateEdges). The
# default-fold merge edge @ hostScopeId is constructor-built; the provides+routes
# edges are the CAPTURE from the per-host materializeUnified fold (Task 18.2),
# passed in as `capturedEdges` (no longer re-derived from subtreeProvides /
# subtreeRoutes). resolve.nix collects this output into the production edge object.
#
# `just ci fx-instantiate-edges` runs this suite.
{ denTest, lib, ... }:
{
  flake.tests.fx-instantiate-edges = {

    # A host(scope "host=igloo") + user(scope "host=igloo/user=tux") topology.
    # The host carries a nixos bucket (perScope), and a user→host route nests the
    # user's homeManager content into the host's nixos at a path. The surfaced
    # edge set must contain BOTH the host nixos default-fold merge edge (target
    # root = host, mode "merge", path [], CONSTRUCTOR-built) AND the user→host
    # route edge (target class "nixos", mode "nest"), the latter coming from the
    # CAPTURED edge list passed through unchanged.
    test-host-user-edge-set = denTest (
      { den, lib, ... }:
      let
        edges = den.lib.aspects.fx.edges.instantiateSubtree;

        hostSid = "host=igloo";
        userSid = "host=igloo/user=tux";

        # id_hash-bearing entity records so scopeName renders "<kind>:<id_hash>"
        # (the unified normalization the real per-host walk uses).
        scopeContexts = {
          ${hostSid} = {
            host = {
              name = "igloo";
              id_hash = "hh";
            };
          };
          ${userSid} = {
            host = {
              name = "igloo";
              id_hash = "hh";
            };
            user = {
              name = "tux";
              id_hash = "uu";
            };
          };
        };
        scopeEntityKind = {
          ${hostSid} = "host";
          ${userSid} = "user";
        };
        edgeMod = import ../../../../nix/lib/aspects/fx/edges/edge.nix { inherit lib; };
        scopeName = edgeMod.scopeName { inherit scopeEntityKind scopeContexts; };

        # The CAPTURED provides+routes edge list the per-host fold would dispatch:
        # here a single user→host route edge (homeManager nested into nixos at a
        # path). In production this list is materializeUnified{exposeEdges}.edges;
        # the suite builds an equivalent record directly via the edge constructor.
        capturedEdges = [
          (edgeMod.mkEdge {
            source = edgeMod.collected (scopeName userSid) "homeManager";
            target = edgeMod.rootTarget (scopeName hostSid) "nixos";
            path = [
              "home-manager"
              "users"
              "tux"
            ];
            mode = "nest";
            annotations = { };
          })
        ];

        result = edges.mkInstantiateEdges {
          name = scopeName;
          scopeParent = {
            ${userSid} = hostSid;
          };
          scopeIsolated = { };
          hostScopeId = hostSid;
          subtreeScopeIds = [
            hostSid
            userSid
          ];
          # The host carries a nixos bucket → a nixos default-fold merge edge.
          perScope = {
            ${hostSid} = {
              nixos = [ { config = { }; } ];
            };
          };
          inherit capturedEdges;
        };

        hostFold = lib.filter (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.source ? collected
          && e.source.collected.scope == scopeName hostSid
          && e.source.collected.class == "nixos"
          && e.target ? root
          && e.target.root == scopeName hostSid
          && e.target.class == "nixos"
        ) result;

        userRoute = lib.filter (
          e:
          e.mode == "nest"
          && e.target.class == "nixos"
          &&
            e.path == [
              "home-manager"
              "users"
              "tux"
            ]
        ) result;
      in
      {
        expr = {
          hostFoldCount = builtins.length hostFold;
          userRouteCount = builtins.length userRoute;
        };
        expected = {
          # The default fold is constructor-built; the route edge passed through
          # from capturedEdges unchanged.
          hostFoldCount = 1;
          userRouteCount = 1;
        };
      }
    );

  };
}
