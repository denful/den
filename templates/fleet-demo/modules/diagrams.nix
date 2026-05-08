# Aspect resolution diagrams for fleet-demo.
#
# Renders views for hosts, users, and the fleet into organized
# subdirectories under diagrams/:
#
#   diagrams/
#     hosts/<host>/              — per-host views + DAG
#     hosts/<host>/users/<user>/ — per-user views
#     fleet/                     — fleet-wide views
{
  den,
  lib,
  ...
}:
let
  inherit (den.lib) diag;

  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);

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

      # Patched mermaid-cli: swap bundled mermaid for 11.14.0.
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

      fleetData = diag.fleet.of { flakeName = "fleet-demo"; };

      renderUsers = true;

      hostViewDefs = classes: rc.views.host ++ rc.views.classViews classes;
      userViewDefs = classes: rc.views.user ++ rc.views.classViews classes;
      fleetViewDefs = rc.views.fleet;

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

      # --- User entries ---

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

      # --- Fleet entries ---

      fleetEntriesList = diag.export.fleetEntries { inherit pkgs; } {
        inherit fleetData;
        viewDefs = fleetViewDefs;
      };

      # --- Pipe flow entries ---

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

      fleetViewEntries =
        mkFleetEntries "pipe-flow" pipeFlowView
        ++ mkFleetEntries "scope-topology" scopeTopoView
        ++ mkFleetEntries "aspect-matrix" aspectMatrixView
        ++ mkFleetEntries "policy-resolution" policyMapView;

      # --- Assembly ---

      everyEntry = hostEntries ++ userEntries ++ fleetEntriesList ++ fleetViewEntries;
      allPackages = entriesToPackages everyEntry;

      # --- Galleries ---

      hostGalleries = map (host: {
        path = "diagrams/hosts/${host.name}.md";
        drv = mkGallery pkgs {
          name = host.name;
          dir = "hosts/${host.name}";
          title = "Gallery: ${host.name}";
          entries = everyEntry;
        };
      }) allHosts;

      fleetGallery = {
        path = "diagrams/fleet.md";
        drv = mkGallery pkgs {
          name = "fleet";
          dir = "fleet";
          title = "Fleet Gallery";
          entries = everyEntry;
        };
      };

      galleries = hostGalleries ++ [ fleetGallery ];

      # --- Fleet-level views from captureFleet ---
      fleetCapture = diag.captureFleet { };

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

      readmeDrv = pkgs.writeText "README.md" ''
        # Fleet Demo Diagrams

        Aspect-resolution visualization for fleet-demo.

        ## Topology

        ```
        flake → fleet → environment:prod → lb-prod, web-prod-1, web-prod-2
                       → environment:staging → web-staging
        ```

        ## Quirk/Pipe Flow

        - `http-backends`: nginx aspects emit backend data, haproxy collects via pipe.collect
        - `host-addrs`: every host emits addr, hostfile collects via pipe.collect

        ## Usage

        ```bash
        nix run --override-input den . .#write-diagrams
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
            destExpr = ''"$(${pkgs.git}/bin/git rev-parse --show-toplevel)/templates/fleet-demo"'';
          };
        };
    };
}
