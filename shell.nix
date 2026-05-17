let
  lock = builtins.fromJSON (builtins.readFile ./templates/ci/flake.lock);
  nixpkgs =
    with lock.nodes.nixpkgs.locked;
    builtins.fetchTarball {
      url = url;
      sha256 = narHash;
    };
in
{
  pkgs ? import nixpkgs { },
  lib ? pkgs.lib,
  ...
}:
pkgs.mkShell {
  buildInputs = with pkgs; [
    jq
    just
    nix-unit
    npins
    pnpm
    nodejs
    hyperfine
    nix-eval-jobs
    ripgrep
  ];
}
