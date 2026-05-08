{

  # A class for flake-parts' perSystem.packages
  # NOTE: this is different from Den's flake-packages class.
  den.ctx.flake-parts.into.flake-parts-system = _: [ { fromClass = _: "packages"; } ];
}
