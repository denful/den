{ den, inputs, ... }:
{
  imports = [ inputs.devshell.flakeModule ];
  den.ctx.flake-parts.into.flake-parts-system = _: [
    {
      fromClass = _: "devshell";
      intoPath = _: [
        "devshells"
        "default"
      ];
    }
  ];
}
