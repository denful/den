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

      # --- Assembly ---

      everyEntry = hostEntries ++ userEntries ++ homeEntries ++ fleetEntriesList;
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

        ## Usage

        ```bash
        nix run .#write-diagrams    # writes all views
        ```
      '';
    in
    {
      packages = allPackages // {
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
