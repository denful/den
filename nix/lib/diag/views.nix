# Standard view definitions for aspect-resolution diagrams.
#
# Each view is a record describing what to compute from a graph IR
# and how to present it. Views are returned as lists so templates can
# extend (`++ [ myView ]`), filter (`builtins.filter`), or replace
# individual entries.
#
# Usage from a template:
#
#   rc = diag.renderContext { inherit pkgs theme; mermaidConfig = elkCfg; };
#   hostViewDefs = diag.views.host rc;
#
#   # Extend with a custom view:
#   hostViewDefs = (diag.views.host rc) ++ [ myCustomView ];
#
#   # Drop a view:
#   hostViewDefs = builtins.filter (v: v.view != "pipeline")
#     (diag.views.host rc);
#
# Fields per view entry:
#
#   view      — short identifier (used in file name: `<entity>-<view>.md`)
#   title     — markdown heading
#   altText   — SVG alt text
#   mdLang    — fenced code block language (`mermaid`, `plantuml`, `json`)
#   svgInfix  — `mmd`/`puml`/`dot`/null; inserted before `.svg` in filename
#   svgFn     — base → source → derivation (null = no SVG render)
#   compute   — graph → source string
#
{ graph, toJSON }:
let
  mmd = svgFn: {
    mdLang = "mermaid";
    svgInfix = "mmd";
    inherit svgFn;
  };
  puml = svgFn: {
    mdLang = "plantuml";
    svgInfix = "puml";
    inherit svgFn;
  };
  json = {
    mdLang = "json";
    svgInfix = null;
    svgFn = null;
  };
  # Raw format: bypasses markdown wrapping, outputs file directly.
  # Used for JSON IR that should be piped through jq.
  raw = ext: {
    mdLang = null;
    svgInfix = null;
    svgFn = null;
    rawExt = ext;
  };

  # mkView — canonical constructor for a single view entry.
  #
  # view    — short identifier
  # title   — markdown heading / SVG alt text (altText defaults to title)
  # altText — override SVG alt text when it differs from title
  # fmt     — mmd/puml/json format attrs (from helpers above)
  # compute — graph → source string
  mkView =
    {
      view,
      title,
      altText ? title,
      fmt,
      compute,
    }:
    {
      inherit
        view
        title
        altText
        compute
        ;
    }
    // fmt;

  self = {

    # --- Entity-agnostic core views ---
    #
    # Shared foundation for every entity kind (host, user, home, …).
    # Default views: the essential set for understanding resolution.
    core =
      {
        render,
        renderDense,
        mmdSourceToSvg,
        ...
      }:
      [
        (mkView {
          view = "aspects";
          title = "Aspect Hierarchy";
          altText = "Aspect hierarchy";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.aspectsOnly g);
        })

        (mkView {
          view = "scope-seq";
          title = "Scope Sequence";
          altText = "Scope sequence";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toSequenceMermaid g;
        })

        (mkView {
          view = "scope-seq-full";
          title = "Scope Sequence (expanded)";
          altText = "Scope sequence expanded";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toSequenceMermaidExpanded g;
        })

        (mkView {
          view = "policy-seq";
          title = "Policy Sequence";
          altText = "Policy sequence";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toPolicySequenceMermaid g;
        })

        (mkView {
          view = "providers";
          title = "Provider Tree";
          altText = "Providers";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.providersOnly g);
        })

        (mkView {
          view = "ir";
          title = "Graph IR (JSON)";
          altText = "IR JSON";
          fmt = raw "json";
          compute = g: toJSON g;
        })
      ];

    # Extended views: available for opt-in but not in the default set.
    extended =
      {
        render,
        renderDense,
        mmdSourceToSvg,
        ...
      }:
      [
        (mkView {
          view = "ctx";
          title = "Context Hierarchy";
          altText = "Context hierarchy";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.contextOnly g);
        })

        (mkView {
          view = "simple";
          title = "Simplified View";
          altText = "Simplified";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.simplified g);
        })

        (mkView {
          view = "scope-edges";
          title = "Scope Topology";
          altText = "Scope edges";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toScopeEdgesMermaid g;
        })

        (mkView {
          view = "providers-resolved";
          title = "Providers Resolved";
          altText = "Provider resolution";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.providersResolved g);
        })

        (mkView {
          view = "adapters";
          title = "Adapter Impact";
          altText = "Adapters";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.adaptersOnly g);
        })

        (mkView {
          view = "decisions";
          title = "Structural Decisions";
          altText = "Decisions";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.decisionsView g);
        })

        (mkView {
          view = "declared";
          title = "User-Declared Aspects";
          altText = "Declared";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.userDeclaredOnly g);
        })

        (mkView {
          view = "diff-classes";
          title = "Class Diff";
          altText = "Class diff";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.diffClasses g);
        })
      ];

    # --- Dynamic per-class views ---
    #
    # Generated from the graph's available classes. Each class gets a
    # slice view showing only the aspects that contribute to that class.
    classViews =
      {
        renderDense,
        mmdSourceToSvg,
        ...
      }:
      classes:
      map (
        className:
        mkView {
          view = "class-${className}";
          title = "Class Slice: ${className}";
          altText = "${className} slice";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.classSlice className g);
        }
      ) classes;

    # --- Per-entity views (host): core + class views ---
    host = rc: self.core rc;

    # --- Per-entity views (user): core only ---
    user = rc: self.core rc;

    # --- Per-entity views (home): core only ---
    home = rc: self.core rc;

    # --- Fleet-level views (flake-wide, host-independent) ---
    fleet =
      {
        render,
        renderDense,
        mmdSourceToSvg,
        ...
      }:
      [
        (mkView {
          view = "namespace";
          title = "Aspect Namespace (declarations)";
          altText = "Aspect namespace";
          fmt = mmd mmdSourceToSvg;
          compute = _: renderDense.toMermaid (graph.ofNamespace { });
        })

        (mkView {
          view = "provider-matrix";
          title = "Fleet Provider Matrix";
          altText = "Provider matrix";
          fmt = mmd mmdSourceToSvg;
          compute = render.toFleetProviderMatrix;
        })
      ];
  };
in
self
