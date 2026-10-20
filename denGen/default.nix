{ gen }:
let
  # nest pattern: each lib/*.nix is `denGen: { <name> = …; }` and sees the merged set.
  # file arg stays plain `denGen:` — destructuring it would force the fixpoint.
  files = builtins.filter (f: builtins.match ".*\\.nix" f != null) (
    builtins.attrNames (builtins.readDir ./lib)
  );
  denGen = builtins.foldl' (acc: f: acc // import (./lib + "/${f}") denGen) { inherit gen; } files;
in
denGen
