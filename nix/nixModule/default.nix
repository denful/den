{ config, ... }@args:
{
  _module.args.den = config.den;
  imports = map (f: import f (args // { den = config.den; })) [
    ./lib.nix
    ./policies.nix
    ./aspects.nix
    ./pipes.nix
  ];
}
