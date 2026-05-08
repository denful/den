# Export helpers: turn view definitions into derivation entries.
#
# Each helper produces a list of `{ name, view, ext, tool, drv }`
# records that templates iterate to build packages and files.
#
# Templates compose these with their own gallery/README builders:
#
#   entries = diag.export.ofViews { inherit pkgs rc; }
#     allHosts hostViewDefs fleetData fleetViewDefs;
#
{ lib }:
let
  # --- Naming conventions ---

  # File name: <view>[.<tool>].<ext>  (entity name is in the directory)
  entryFileName =
    e:
    let
      toolInfix = if e.tool != null then ".${e.tool}" else "";
    in
    "${e.view}${toolInfix}.${e.ext}";

  # Package name: <name>-<view>[-<tool>][-<ext>] (nix-safe, flat)
  entryPackageName =
    e:
    let
      base = "${e.name}-${e.view}";
      toolSuffix = if e.tool != null then "-${e.tool}" else "";
      extSuffix = if e.ext == "svg" then "-svg" else "";
    in
    "${base}${toolSuffix}${extSuffix}";

  entryRelPath = e: "diagrams/${e.dir}/${entryFileName e}";

  # --- Md wrapper builders ---

  mkViewMd =
    pkgs:
    {
      base,
      viewName,
      title,
      entityName ? null,
      altText,
      svgInfix,
      mdLang,
      source,
    }:
    let
      heading = if entityName != null then "# ${title}: ${entityName}" else "# ${title}";
      imageEmbed = if svgInfix == null then "" else "![${altText}](./${viewName}.${svgInfix}.svg)\n\n";
    in
    # No indentation in heredoc — ${source} may contain zero-indented
    # lines which would prevent Nix from stripping template whitespace.
    pkgs.writeText "${base}.md" ''
      ${heading}

      ${imageEmbed}```${mdLang}
      ${source}
      ```
    '';

  # --- Entry builders ---

  # Single view → [md entry, svg entry?]
  mkViewEntries =
    pkgs: dir: entityName: graph: view:
    let
      source = view.compute graph;
      base = "${entityName}-${view.view}";
      viewName = view.view;
      isRaw = view ? rawExt;
      rawExt = view.rawExt or null;
      mdDrv = mkViewMd pkgs {
        inherit base viewName source;
        title = view.title;
        inherit entityName;
        inherit (view) altText svgInfix mdLang;
      };
      rawDrv =
        if rawExt == "json" then
          pkgs.runCommand "${base}.${rawExt}" { nativeBuildInputs = [ pkgs.jq ]; } ''
            echo ${lib.escapeShellArg source} | jq . > $out
          ''
        else
          pkgs.writeText "${base}.${rawExt}" source;
      mkEntry = ext: tool: drv: {
        name = entityName;
        view = viewName;
        inherit
          dir
          ext
          tool
          drv
          ;
      };
    in
    if isRaw then
      [ (mkEntry rawExt null rawDrv) ]
    else
      [ (mkEntry "md" null mdDrv) ]
      ++ lib.optional (view.svgFn != null) (mkEntry "svg" view.svgInfix (view.svgFn base source));

  # Multi-format DAG view: one md embedding three SVGs.
  mkDagEntries =
    pkgs:
    {
      renderDense,
      mmdSourceToSvg,
      ...
    }:
    dir: entityName: graph:
    let
      mmdSrc = renderDense.toMermaid graph;
      base = "${entityName}-dag";
      mdDrv = mkViewMd pkgs {
        inherit base;
        viewName = "dag";
        title = "Full DAG";
        inherit entityName;
        altText = "DAG";
        svgInfix = "mmd";
        mdLang = "mermaid";
        source = mmdSrc;
      };
      mkEntry = ext: tool: drv: {
        name = entityName;
        view = "dag";
        inherit
          dir
          ext
          tool
          drv
          ;
      };
    in
    [
      (mkEntry "md" null mdDrv)
      (mkEntry "svg" "mmd" (mmdSourceToSvg base mmdSrc))
    ];

  # Fleet view → [md entry, svg entry]
  mkFleetViewEntries =
    pkgs: fleetData: view:
    let
      source = view.compute fleetData;
      base = "fleet-${view.view}";
      viewName = view.view;
      mdDrv = mkViewMd pkgs {
        inherit base viewName source;
        title = view.title;
        inherit (view) altText svgInfix mdLang;
      };
      svgDrv = view.svgFn base source;
      mkEntry = ext: tool: drv: {
        name = "fleet";
        view = viewName;
        dir = "fleet";
        inherit ext tool drv;
      };
    in
    [ (mkEntry "md" null mdDrv) ]
    ++ lib.optional (view.svgFn != null) (mkEntry "svg" view.svgInfix svgDrv);

  # --- Batch builders ---

  # All entries for one entity (views + dag + optional gallery entry).
  entityEntries =
    {
      pkgs,
      rc,
      diag,
    }:
    {
      entity,
      name,
      dir,
      viewDefs,
      galleryDrv ? null,
    }:
    let
      g =
        if entity ? nodes then
          entity
        else
          throw "entityEntries: entity must be a pre-computed graph (from hostContext, userContext, homeContext, or context).";
    in
    lib.concatMap (mkViewEntries pkgs dir name g) viewDefs
    ++ mkDagEntries pkgs rc dir name g
    ++ lib.optional (galleryDrv != null) {
      inherit name dir;
      view = "gallery";
      ext = "md";
      tool = null;
      drv = galleryDrv;
    };

  # All fleet entries (views + optional gallery entry).
  fleetEntries =
    { pkgs }:
    {
      fleetData,
      viewDefs,
      galleryDrv ? null,
    }:
    lib.concatMap (mkFleetViewEntries pkgs fleetData) viewDefs
    ++ lib.optional (galleryDrv != null) {
      name = "fleet";
      dir = "fleet";
      view = "gallery";
      ext = "md";
      tool = null;
      drv = galleryDrv;
    };

  # Convert a list of entries to a packages attrset.
  entriesToPackages =
    entries:
    lib.listToAttrs (
      map (e: {
        name = entryPackageName e;
        value = e.drv;
      }) entries
    );

  # Convert entries to files records (for the `files` flake module).
  entriesToFiles =
    entries:
    map (e: {
      path_ = entryRelPath e;
      inherit (e) drv;
    }) entries;

  # Shell script line that copies one entry to the output dir.
  entryCopyLine = e: ''cat ${e.drv} > "$dest/${entryRelPath e}"'';

  # Unique directory paths for mkdir -p in write scripts.
  entryDirs = entries: lib.unique (map (e: "diagrams/${e.dir}") entries);

  # --- Filter helpers ---

  # Filter entities by a renderList: true = all, list = by name, false = none.
  filterByRender =
    {
      all,
      renderList,
      getKey ? x: x.name or "",
    }:
    if renderList == true then
      all
    else if builtins.isList renderList then
      builtins.filter (x: builtins.elem (getKey x) renderList) all
    else
      [ ];

  # --- Gallery generation ---

  # Extract unique SVG views for a directory from entry list.
  svgViewsForDir =
    dir: entries:
    lib.unique (
      map (e: {
        inherit (e) view;
        tool = e.tool;
      }) (builtins.filter (e: e.dir == dir && e.ext == "svg") entries)
    );

  # Build a gallery markdown file for a directory.
  mkGallery =
    pkgs:
    {
      name,
      dir,
      title,
      entries,
    }:
    let
      svgs = svgViewsForDir dir entries;
      subdir = builtins.baseNameOf dir;
      embedLine =
        sv:
        let
          toolInfix = if sv.tool != null then ".${sv.tool}" else "";
          file = "${sv.view}${toolInfix}.svg";
        in
        "## ${sv.view}\n\n![${sv.view}](./${subdir}/${file})";
      body = lib.concatStringsSep "\n\n" (map embedLine svgs);
    in
    pkgs.writeText "${name}-gallery.md" ''
      # ${title}

      ${body}
    '';

  # --- Write script assembly ---

  # Build a write-diagrams script that copies all entries + galleries to a target directory.
  mkWriteScript =
    pkgs:
    {
      entries,
      galleries ? [ ],
      readmeDrv ? null,
      destExpr ? ''"$(${pkgs.git}/bin/git rev-parse --show-toplevel)"'',
      scriptName ? "write-diagrams",
    }:
    let
      dirs = entryDirs entries;
      mkdirLines = lib.concatMapStringsSep "\n" (d: ''mkdir -p "$dest/${d}"'') dirs;
      writeLines = lib.concatMapStringsSep "\n" entryCopyLine entries;
      galleryWriteLines = lib.concatMapStringsSep "\n" (
        g: ''cat ${g.drv} > "$dest/${g.path}"''
      ) galleries;
    in
    pkgs.writeShellScriptBin scriptName ''
      set -euo pipefail
      dest=${destExpr}
      rm -rf "$dest/diagrams"
      ${mkdirLines}
      ${writeLines}
      ${galleryWriteLines}
      ${lib.optionalString (readmeDrv != null) ''cat ${readmeDrv} > "$dest/README.md"''}
      echo "Wrote $(find "$dest/diagrams" -type f | wc -l) files to $dest/diagrams/"
    '';

in
{
  inherit
    mkViewEntries
    mkDagEntries
    mkFleetViewEntries
    entityEntries
    fleetEntries
    entriesToPackages
    entriesToFiles
    entryCopyLine
    entryDirs
    entryFileName
    entryPackageName
    entryRelPath
    filterByRender
    svgViewsForDir
    mkGallery
    mkWriteScript
    ;
}
