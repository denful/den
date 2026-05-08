{ inputs, ... }:
{
  imports = [ inputs.files.flakeModules.default ];
  den.ctx.flake-parts.into.flake-parts-system = _: [ { fromClass = _: "files"; } ];
}
