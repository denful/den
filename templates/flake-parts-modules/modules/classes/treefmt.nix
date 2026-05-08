{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.ctx.flake-parts.into.flake-parts-system = _: [ { fromClass = _: "treefmt"; } ];
}
