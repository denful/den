{ den, inputs, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  imports = [ inputs.files.flakeModules.default ];
  den.classes.files = { };
  den.policies.flake-parts-to-flake-parts-system-files =
    {
      __entityKind ? null,
      ...
    }:
    if __entityKind != "flake-parts" then
      [ ]
    else
      [ (resolve.to "flake-parts-system" { fromClass = "files"; }) ];
}
