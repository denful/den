# Register flake-level and default routing kinds in den.schema.
#
# These are routing kinds — they participate in binding key derivation
# but don't define entity instances. The empty module body means the
# schemaEntryType merge sets isEntity = false automatically.
{ lib, ... }:
let
  flakeKinds = [
    "flake"
    "flake-system"
    "flake-os"
    "flake-hm"
    "flake-packages"
    "flake-apps"
    "flake-checks"
    "flake-devShells"
    "flake-legacyPackages"
    "default"
  ];
in
{
  den.schema = lib.genAttrs flakeKinds (_: { });
}
