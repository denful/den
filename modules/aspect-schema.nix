# Collect class declarations from aspects and merge into den.classes.
#
# Aspects can declare:
#   den.aspects.foo.classes.hjem = { description = "..."; };
#
# These are folded into den.classes so the
# schema registry sees them alongside manual declarations.
{
  lib,
  config,
  ...
}:
let
  # Collect classes from an aspects attrset (freeform aspect submodules).
  collectFromAspects =
    aspects:
    let
      aspectNames = builtins.attrNames aspects;
      # Only access classes if the aspect defines them — avoid forcing
      # freeform keys that might be class modules.
      perAspect = map (
        aName:
        let
          a = aspects.${aName};
        in
        {
          classes = a.classes or { };
        }
      ) aspectNames;
    in
    {
      classes = lib.foldl' (acc: x: acc // x.classes) { } perAspect;
    };

  # Collect from top-level den.aspects
  topLevel = collectFromAspects (config.den.aspects or { });

  # Collect from all den.ful namespaces
  structuralKeys = [
    "stages"
    "schema"
    "classes"
    "_module"
  ];
  nsNames = builtins.attrNames (config.den.ful or { });
  nsCollected = map (
    nsName:
    let
      ns = config.den.ful.${nsName};
      # Namespace freeform keys are aspects; filter out structural keys.
      aspectNames = builtins.filter (k: !builtins.elem k structuralKeys) (builtins.attrNames ns);
      aspects = lib.genAttrs aspectNames (k: ns.${k});
    in
    collectFromAspects aspects
  ) nsNames;

  # Namespace-level class declarations (den.ful.<ns>.classes)
  nsLevelClasses = lib.foldl' (
    acc: nsName: acc // (config.den.ful.${nsName}.classes or { })
  ) { } nsNames;

  allClasses = lib.foldl' (acc: x: acc // x.classes) (topLevel.classes // nsLevelClasses) nsCollected;
in
{
  config.den = {
    classes = allClasses;
  };
}
