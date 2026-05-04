# Re-exports for the aspect/ directory.
{
  lib,
  den,
}:
{ ctxFromHandlers }:
let
  children = import ./children.nix { inherit lib den; };
  provide = import ./provide.nix { inherit lib den; } { inherit ctxFromHandlers; };
in
{
  inherit (children) emitIncludes registerConstraints;
  inherit (provide) emitAspectPolicies;
}
