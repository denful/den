{ inputs, lib, ... }:
let
  lock = builtins.fromJSON (builtins.readFile ../../templates/ci/flake.lock);
  locked = lock.nodes.nix-effects.locked;
  nix-effects = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
    sha256 = locked.narHash;
  };
  nfx = import nix-effects { inherit lib; };
in
inputs.nix-effects.lib or nfx
