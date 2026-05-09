# Resolve flake-parts class and import into perSystem.
{ den, ... }:
let
  perSystemModule = den.lib.aspects.resolve "flake-parts" (den.lib.resolveEntity "flake-parts" { });
in
{
  perSystem.imports = [ perSystemModule ];
}
