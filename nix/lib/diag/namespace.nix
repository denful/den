# Static namespace graph builder.
#
# Walks `den.aspects` declarations (no host resolution) and builds a
# graph IR showing authored building blocks and their static inclusions.
{
  lib,
  util,
  graphLib,
  aspects ? { },
}:
let
  defaultAspects = aspects;
  namespaceGraph =
    {
      name ? "aspects",
      aspects ? defaultAspects,
      direction ? "TD",
      filter ? (_: true),
    }:
    let
      sanitize = util.makeIdSanitizer "ns";
      isAspect =
        v: builtins.isAttrs v && v ? includes && v ? name && v ? meta && builtins.isAttrs (v.meta or null);
      entries = lib.filterAttrs (_: v: isAspect v && filter v) aspects;
      aspectNames = builtins.attrNames entries;

      refToName =
        ref:
        if !builtins.isAttrs ref then
          null
        else if ref ? name && entries ? ${ref.name} then
          ref.name
        else
          null;

      staticIncludes =
        value:
        let
          incs = value.includes or [ ];
        in
        if builtins.isList incs then incs else [ ];

      mkNode =
        name: value:
        let
          incs = staticIncludes value;
          hasFunctorInclude = lib.any (i: !builtins.isAttrs i) incs;
          hasConstraint = (value.meta.handleWith or null) != null;
          hasProvides = (value.provides or { }) != { };
          providerChain = value.meta.provider or [ ];
        in
        graphLib.emptyNode
        // {
          id = sanitize name;
          label = name;
          fullLabel = name;
          shape =
            if hasFunctorInclude then
              "hexagon"
            else if hasProvides then
              "trapezoid"
            else
              "rect";
          style = if hasConstraint then "adapter" else "default";
          providerPath = providerChain;
          hasClass = true;
        };

      mkEdges =
        name: value:
        let
          incs = staticIncludes value;
          fromId = sanitize name;
        in
        lib.concatMap (
          i:
          let
            target = refToName i;
          in
          lib.optional (target != null && target != name) {
            from = fromId;
            to = sanitize target;
            style = "normal";
            label = null;
          }
        ) incs;

      allNodes = lib.mapAttrsToList mkNode entries;
      declEdges = lib.concatMap (n: mkEdges n entries.${n}) aspectNames;

      rootId = sanitize name;
      includedTargets = lib.listToAttrs (
        map (e: {
          name = e.to;
          value = true;
        }) declEdges
      );
      rootEdges = lib.concatMap (
        aname:
        let
          nid = sanitize aname;
        in
        lib.optional (!(includedTargets ? ${nid})) {
          from = rootId;
          to = nid;
          style = "normal";
          label = null;
        }
      ) aspectNames;
    in
    {
      rootName = name;
      inherit rootId direction;
      nodes = allNodes;
      edges = rootEdges ++ declEdges;
      entityKinds = [ ];
      entityEdges = [ ];
    };
in
namespaceGraph
