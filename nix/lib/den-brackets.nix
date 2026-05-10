{
  lib,
  config,
  ...
}:
_nixPath: name:
let
  # Resolve a provides sub-path on an aspect, falling back to the provides
  # namespace with a deprecation warning when the key isn't a direct child.
  resolveWithProvidesFallback =
    aspect: subPath:
    let
      head = lib.head subPath;
      tail = lib.tail subPath;
      # Direct key on the aspect takes priority (new-style direct nesting)
      direct = aspect.${head} or null;
      # Fall back to provides namespace (deprecated path)
      provided = (aspect.provides or { }).${head} or null;
      resolved =
        if direct != null then
          direct
        else if provided != null then
          lib.warn "den: bracket path uses 'provides.${head}' — migrate to direct nesting at key '${head}'" provided
        else
          throw "Aspect '${aspect.name or "<unknown>"}' has no key '${head}' (checked direct and provides)";
    in
    if tail == [ ] then resolved else resolveWithProvidesFallback resolved tail;

  findAspect =
    path:
    let
      head = lib.head path;
      tail = lib.tail path;
    in
    if head == "den" then
      let
        # <den/X/Y> — when X is a den.batteries provider, resolve through
        # that provider with provides fallback for deeper keys.
        firstTail = if tail != [ ] then lib.head tail else null;
        isProvider = firstTail != null && builtins.hasAttr firstTail config.den.batteries;
      in
      if isProvider then
        let
          provider = config.den.batteries.${firstTail};
          rest = lib.tail tail;
        in
        if rest == [ ] then provider else resolveWithProvidesFallback provider rest
      else
        lib.getAttrFromPath ([ "den" ] ++ tail) config
    else if builtins.hasAttr head config.den.aspects then
      let
        aspect = config.den.aspects.${head};
      in
      if tail == [ ] then aspect else resolveWithProvidesFallback aspect tail
    else if lib.hasAttrByPath [ "ful" head ] config.den then
      let
        ns = config.den.ful.${head};
        denfulTail = tail;
      in
      if denfulTail == [ ] then
        ns
      else
        let
          firstKey = lib.head denfulTail;
          nsAspect = ns.${firstKey} or null;
          rest = lib.tail denfulTail;
        in
        if nsAspect == null then
          throw "Namespace '${head}' has no aspect '${firstKey}'"
        else if rest == [ ] then
          nsAspect
        else
          resolveWithProvidesFallback nsAspect rest
    else
      throw "Aspect not found: ${lib.concatStringsSep "." path}";
in
lib.pipe name [
  (lib.strings.replaceStrings [ "/" ] [ "." ])
  (lib.strings.splitString ".")
  findAspect
]
