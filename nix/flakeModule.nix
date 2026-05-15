{ lib, ... }@args:
{
  imports =
    builtins.filter (p: lib.hasSuffix ".nix" p && !lib.hasInfix "/_" p) (
      lib.filesystem.listFilesRecursive ../modules
    )
    ++ lib.optional (args ? inputs && args.inputs ? flake-parts && !(args ? __denTest)) (
      # Auto-bridge routed flake content to all declared top-level options.
      # Only activates under flake-parts (where top-level options exist).
      {
        den,
        lib,
        options,
        ...
      }:
      let
        routed = den.lib.flakeRouted or { };
        internalKeys = [
          "_module"
          "warnings"
          "assertions"
          "flake"
          "den"
          "perSystem"
          "systems"
        ];
        bridgeKeys = lib.subtractLists internalKeys (builtins.attrNames options);
      in
      {
        config = lib.genAttrs bridgeKeys (k: lib.mkIf (routed ? ${k}) routed.${k});
      }
    );
}
