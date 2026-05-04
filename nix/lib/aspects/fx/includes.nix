{ ... }:
let
  # Conditional inclusion based on a guard function.
  # The guard receives { hasAspect = ref: bool; } where hasAspect checks the
  # path set accumulated so far during resolution. Because resolution is sequential
  # (left-to-right through includes), guards can only see aspects resolved BEFORE
  # them in the tree. Reordering includes may change which guards pass.
  includeIf = guardFn: aspects: {
    name = "<includeIf>";
    meta = {
      guard = guardFn;
      aspects = aspects;
    };
    includes = [ ];
  };

in
{
  inherit includeIf;
}
