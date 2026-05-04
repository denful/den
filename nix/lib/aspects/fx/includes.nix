_:
let
  includeIf = guardFn: aspects: {
    name = "<includeIf>";
    meta = {
      guard = guardFn;
      inherit aspects;
    };
    includes = [ ];
  };
in
{
  inherit includeIf;
}
