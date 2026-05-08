# Standard flake-parts wiring for den templates.
{ inputs, den, ... }:
{
  systems = builtins.attrNames den.hosts;

  imports = [
    inputs.den.flakeModules.default
  ];

  _module.args.inputs = inputs;
}
