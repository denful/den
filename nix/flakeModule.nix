{ lib, ... }:
{
  imports = builtins.filter (p: lib.hasSuffix ".nix" p && !lib.hasInfix "/_" p) (
    lib.filesystem.listFilesRecursive ../modules
  );
}
