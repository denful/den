# Aspect resolution diagrams.
#
# Renders views for hosts, users, homes, and the fleet into organized
# subdirectories under diagrams/:
#
#   diagrams/
#     hosts/<host>/         — per-host views + DAG
#     users/<host>-<user>/  — per-user views (optional)
#     homes/<home>/         — per-home views
#     fleet/                — fleet-wide views
#
# User/home rendering is opt-in via `renderUsers` / `renderHomes`.
{
  den,
  lib,
  self,
  ...
}:
let
  inherit (den.lib) diag;

  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);

  # Base16 scheme name used for all rendered views.
  themeScheme = "catppuccin-mocha";

in
{
  perSystem =
    { pkgs, ... }:
    let
      theme = diag.themeFromBase16 {
        inherit pkgs;
        scheme = themeScheme;
      };

      # Patched mermaid-cli: swap bundled mermaid@11.12.0 for 11.14.0
      # so recent diagram types render. Drop once nixpkgs bundles ≥11.14.
      mermaidCliPatched = pkgs.mermaid-cli.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          mermaid_dir="$out/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/mermaid"
          if [ ! -d "$mermaid_dir" ]; then
            echo "mermaidCliPatched: expected $mermaid_dir to exist." >&2
            exit 1
          fi
          rm -rf "$mermaid_dir"
          mkdir -p "$mermaid_dir"
          ${pkgs.gnutar}/bin/tar -xzf ${
            pkgs.fetchurl {
              url = "https://registry.npmjs.org/mermaid/-/mermaid-11.14.0.tgz";
              hash = "sha256-Y7oGZJ4X4Q/uAuVMfC7az+JQtLvds8JJfwDToypC5cc=";
            }
          } -C "$mermaid_dir" --strip-components=1
        '';
      });

      rc = diag.renderContext {
        inherit pkgs theme;
        mermaidCli = mermaidCliPatched;
        mermaidConfig = {
          layout = "elk";
          elk = {
            mergeEdges = true;
            nodePlacementStrategy = "BRANDES_KOEPF";
          };
          flowchart = {
            wrappingWidth = 600;
          };
        };
      };

      fleetData = diag.fleet.of { flakeName = "diagram-demo"; };

      # --- Render control ---
      #
      # Set to a list of user names to render only those users, or true
      # for all users, or false/[] for none. Same for homes.
      renderUsers = true;
      renderHomes = true;

      # View definitions. Class views are appended dynamically per entity.
      hostViewDefs = classes: rc.views.host ++ rc.views.classViews classes;
      userViewDefs = classes: rc.views.user ++ rc.views.classViews classes;
      homeViewDefs = classes: rc.views.home ++ rc.views.classViews classes;
      fleetViewDefs = rc.views.fleet;

      # --- Helpers ---

      inherit (diag.export)
        entityEntries
        filterByRender
        mkGallery
        mkWriteScript
        entriesToPackages
        entriesToFiles
        ;

      graphClasses = entity: lib.unique (lib.concatMap (n: n.classes or [ ]) entity.nodes);

      # --- Host entries ---

      hostEntries = lib.concatMap (
        host:
        let
          entity = diag.hostContext { inherit host; };
        in
        entityEntries { inherit pkgs rc diag; } {
          inherit entity;
          name = host.name;
          dir = "hosts/${host.name}";
          viewDefs = hostViewDefs (graphClasses entity);
        }
      ) allHosts;

      # --- User entries (optional) ---

      allUsers = lib.concatMap (
        host:
        lib.mapAttrsToList (userName: user: {
          inherit host user userName;
          name = "${host.name}-${userName}";
        }) (host.users or { })
      ) allHosts;

      filteredUsers = filterByRender {
        all = allUsers;
        renderList = renderUsers;
        getKey = u: u.userName;
      };

      userEntries = lib.concatMap (
        u:
        let
          entity = diag.userContext { inherit (u) host user; };
        in
        entityEntries { inherit pkgs rc diag; } {
          inherit entity;
          name = u.userName;
          dir = "hosts/${u.host.name}/users/${u.userName}";
          viewDefs = userViewDefs (graphClasses entity);
        }
      ) filteredUsers;

      # --- Home entries (optional) ---

      allHomes = lib.concatMap (
        system: lib.mapAttrsToList (key: home: { inherit home key; }) ((den.homes or { }).${system} or { })
      ) (builtins.attrNames (den.homes or { }));

      filteredHomes = filterByRender {
        all = allHomes;
        renderList = renderHomes;
        getKey = h: h.key;
      };

      homeEntries = lib.concatMap (
        h:
        let
          safeName = lib.replaceStrings [ "@" ] [ "-at-" ] h.key;
          entity = diag.homeContext { home = h.home; };
        in
        entityEntries { inherit pkgs rc diag; } {
          inherit entity;
          name = "home-${safeName}";
          dir = "homes/${safeName}";
          viewDefs = homeViewDefs (graphClasses entity);
        }
      ) filteredHomes;

      # --- Fleet entries ---

      fleetEntriesList = diag.export.fleetEntries { inherit pkgs; } {
        inherit fleetData;
        viewDefs = fleetViewDefs;
      };

      # --- Fleet-level views from captureFleet ---
      fleetCapture = diag.captureFleet { };

      # Per-host graph IRs for fleet DAG composition.
      hostGraphs = lib.listToAttrs (
        map (host: {
          name = host.name;
          value = diag.hostContext { inherit host; };
        }) allHosts
      );

      mkFleetView =
        name: title: renderFn:
        let
          source = renderFn fleetCapture;
          md = pkgs.writeText "${name}.md" "# ${title}\n\n![${title}](./${name}.mmd.svg)\n\n```mermaid\n${source}\n```\n";
          svg = rc.mmdSourceToSvg name source;
        in
        {
          inherit md svg;
        };

      # --- Text summaries ---
      fleetSummaryText = diag.text.fleetSummary fleetCapture;
      fleetSummaryDrv = pkgs.writeText "fleet-summary.md" fleetSummaryText;

      hostSummaryDrvs = lib.listToAttrs (
        map (
          host:
          let
            entity = diag.hostContext { inherit host; };
            text = diag.text.hostSummary {
              graph = entity;
              inherit host fleetCapture;
            };
          in
          {
            name = "${host.name}-summary";
            value = pkgs.writeText "${host.name}-summary.md" text;
          }
        ) allHosts
      );

      pipeFlowView = mkFleetView "pipe-flow" "Pipe Flow" rc.render.toPipeFlowMermaid;
      scopeTopoView = mkFleetView "scope-topology" "Scope Topology" rc.render.toScopeTopologyMermaid;
      aspectMatrixView = mkFleetView "aspect-matrix" "Aspect Coverage" rc.render.toAspectMatrixMermaid;
      policyMapView =
        mkFleetView "policy-resolution" "Policy Resolution Map"
          rc.render.toPolicyResolutionMapMermaid;
      pipeSeqView = mkFleetView "pipe-sequence" "Pipe Sequence" rc.render.toPipeSequenceMermaid;
      fleetDagSource = rc.render.toFleetDagMermaid { inherit fleetCapture hostGraphs; };
      fleetIrJson = diag.fleetGraph.toJSON { inherit fleetCapture hostGraphs; };
      fleetIrDrv = pkgs.runCommand "fleet-ir.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
        echo ${lib.escapeShellArg fleetIrJson} | jq . > $out
      '';
      fleetDagView = {
        md = pkgs.writeText "fleet-dag.md" "# Fleet DAG\n\n![Fleet DAG](./fleet-dag.mmd.svg)\n\n```mermaid\n${fleetDagSource}\n```\n";
        svg = rc.mmdSourceToSvg "fleet-dag" fleetDagSource;
      };

      # --- Fleet view entries ---

      mkFleetEntries = viewName: view: [
        {
          name = "fleet";
          view = viewName;
          dir = "fleet";
          ext = "md";
          tool = null;
          drv = view.md;
        }
        {
          name = "fleet";
          view = viewName;
          dir = "fleet";
          ext = "svg";
          tool = "mmd";
          drv = view.svg;
        }
      ];

      mkTextEntry = name: dir: drv: {
        inherit name dir drv;
        view = "summary";
        ext = "md";
        tool = null;
      };

      textEntries = [
        (mkTextEntry "fleet" "fleet" fleetSummaryDrv)
      ]
      ++ map (
        host: mkTextEntry host.name "hosts/${host.name}" hostSummaryDrvs."${host.name}-summary"
      ) allHosts;

      fleetViewEntries =
        mkFleetEntries "pipe-flow" pipeFlowView
        ++ mkFleetEntries "scope-topology" scopeTopoView
        ++ mkFleetEntries "aspect-matrix" aspectMatrixView
        ++ mkFleetEntries "policy-resolution" policyMapView
        ++ mkFleetEntries "pipe-sequence" pipeSeqView
        ++ mkFleetEntries "fleet-dag" fleetDagView
        ++ [
          {
            name = "fleet";
            view = "fleet-ir";
            dir = "fleet";
            ext = "json";
            tool = null;
            drv = fleetIrDrv;
          }
        ];

      # --- Assembly ---

      everyEntry =
        hostEntries ++ userEntries ++ homeEntries ++ fleetEntriesList ++ fleetViewEntries ++ textEntries;
      allPackages = entriesToPackages everyEntry;
      allFiles = entriesToFiles everyEntry;

      # --- Galleries ---

      hostGalleries = map (
        host:
        let
          dir = "hosts/${host.name}";
        in
        {
          path = "diagrams/hosts/${host.name}.md";
          drv = mkGallery pkgs {
            name = host.name;
            inherit dir;
            title = "Gallery: ${host.name}";
            entries = everyEntry;
          };
        }
      ) allHosts;

      userGalleries = map (
        u:
        let
          dir = "hosts/${u.host.name}/users/${u.userName}";
        in
        {
          path = "diagrams/hosts/${u.host.name}/users/${u.userName}.md";
          drv = mkGallery pkgs {
            name = u.userName;
            inherit dir;
            title = "Gallery: ${u.userName} @ ${u.host.name}";
            entries = everyEntry;
          };
        }
      ) filteredUsers;

      homeGalleries = map (
        h:
        let
          safeName = lib.replaceStrings [ "@" ] [ "-at-" ] h.key;
          dir = "homes/${safeName}";
        in
        {
          path = "diagrams/homes/${safeName}.md";
          drv = mkGallery pkgs {
            name = "home-${safeName}";
            inherit dir;
            title = "Gallery: ${safeName}";
            entries = everyEntry;
          };
        }
      ) filteredHomes;

      fleetGallery = {
        path = "diagrams/fleet.md";
        drv = mkGallery pkgs {
          name = "fleet";
          dir = "fleet";
          title = "Fleet Gallery";
          entries = everyEntry;
        };
      };

      galleries = hostGalleries ++ userGalleries ++ homeGalleries ++ [ fleetGallery ];

      readmeDrv = pkgs.writeText "README.md" ''
        # Diag Demo

        Aspect-resolution visualization via `den.lib.diag`.

        ## Directory Structure

        ```
        diagrams/
          hosts/<host>/    — per-host views (aspects, dag, seq, etc.)
          users/<host>-<user>/ — per-user views
          homes/<home>/    — per-home views
          fleet/           — fleet-wide views
        ```

        ## Hosts

        | Host     | Pattern                                                       |
        | -------- | ------------------------------------------------------------- |
        | `laptop` | Baseline workstation, full tree                               |
        | `server` | Relay role + provider exclusion + prefix filtering             |
        | `devbox` | Dual role + bracket includes + compound exclusions + multi-user |

        ## Per-Host Views

        | View | Description |
        | ---- | ----------- |
        | `dag` | Full DAG (mermaid + dot + puml) |
        | `aspects` | Aspect hierarchy with scope subgraphs |
        | `simple` | Simplified (providers folded) |
        | `ctx` | Context pipeline scopes |
        | `scope-seq` | Scope sequence (compact) |
        | `scope-seq-full` | Scope sequence (expanded) |
        | `policy-seq` | Policy resolution sequence |
        | `scope-edges` | Scope topology |
        | `providers` | Provider hierarchy |
        | `providers-resolved` | Provider → resolved output |
        | `adapters` | Constraint impact |
        | `decisions` | Structural decisions |
        | `declared` | User-declared aspects |
        | `class-<name>` | Per-class slice (dynamic) |
        | `diff-classes` | nixos vs homeManager diff |
        | `c4component` | C4 component view |
        | `ir` | Graph IR (JSON) |

        ## Fleet Views

        | View | Description |
        | ---- | ----------- |
        | `pipe-flow` | Cross-host pipe data flow |
        | `scope-topology` | Scope hierarchy topology |
        | `aspect-matrix` | Aspect coverage matrix |
        | `policy-resolution` | Policy resolution map |
        | `pipe-sequence` | Pipe sequence diagram |
        | `fleet-dag` | Fleet-wide DAG |
        | `fleet-ir` | Graph IR (JSON, for ir-viewer) |
        | `summary` | Text summary (fleet + per-host) |

        ## Usage

        ```bash
        nix run .#write-diagrams    # writes all views
        ```
      '';
    in
    {
      packages =
        allPackages
        // hostSummaryDrvs
        // {
          fleet-summary = fleetSummaryDrv;
        }
        // {
          write-diagrams = mkWriteScript pkgs {
            entries = everyEntry;
            inherit galleries readmeDrv;
            destExpr = ''"$(${pkgs.git}/bin/git rev-parse --show-toplevel)/templates/diagram-demo"'';
          };
        };

      files.gitToplevel = self;
      files.files = allFiles ++ [
        {
          path_ = "README.md";
          drv = readmeDrv;
        }
      ];
    };
}
