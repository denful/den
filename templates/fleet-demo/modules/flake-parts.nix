# Standard flake-parts wiring for den templates.
{ inputs, ... }:
{
  imports = [
    inputs.den.flakeModules.default
  ];

  _module.args.inputs = inputs;
}
