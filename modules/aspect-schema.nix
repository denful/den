# Collect trait/class declarations from aspects and merge into den.schema.
#
# Aspects can declare:
#   den.aspects.foo.traits.firewall = { description = "..."; collection = "list"; };
#   den.aspects.foo.classes.hjem = { description = "..."; };
#
# These are folded into den.schema.traits / den.schema.classes so the
# schema registry sees them alongside manual declarations.
{
  den,
  lib,
  config,
  ...
}:
let
  # Collect traits/classes from an aspects attrset (freeform aspect submodules).
  collectFromAspects =
    aspects:
    let
      aspectNames = builtins.attrNames aspects;
      # Only access traits/classes if the aspect defines them — avoid forcing
      # freeform keys that might be class modules.
      perAspect = map (
        aName:
        let
          a = aspects.${aName};
        in
        {
          traits = a.traits or { };
          classes = a.classes or { };
        }
      ) aspectNames;
    in
    {
      traits = lib.foldl' (acc: x: acc // x.traits) { } perAspect;
      classes = lib.foldl' (acc: x: acc // x.classes) { } perAspect;
    };

  # Collect from top-level den.aspects
  topLevel = collectFromAspects (config.den.aspects or { });

  # Collect from all den.ful namespaces
  structuralKeys = [
    "stages"
    "schema"
    "traits"
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

  # Namespace-level trait/class declarations (den.ful.<ns>.traits / .classes)
  nsLevelTraits = lib.foldl' (
    acc: nsName: acc // (config.den.ful.${nsName}.traits or { })
  ) { } nsNames;
  nsLevelClasses = lib.foldl' (
    acc: nsName: acc // (config.den.ful.${nsName}.classes or { })
  ) { } nsNames;

  allTraits = lib.foldl' (acc: x: acc // x.traits) (topLevel.traits // nsLevelTraits) nsCollected;
  allClasses = lib.foldl' (acc: x: acc // x.classes) (topLevel.classes // nsLevelClasses) nsCollected;
in
{
  config.den.schema = {
    traits = allTraits;
    classes = allClasses;
  };
}
