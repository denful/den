{
  lib,
  config,
  den,
  ...
}:
let

  systemsOpt = lib.mkOption {
    default =
      let
        sys = lib.unique (lib.attrNames den.hosts ++ lib.attrNames den.homes);
      in
      if sys == [ ] then lib.systems.flakeExposed else sys;
    type = lib.types.listOf lib.types.str;
  };

in
{
  options.den.systems = systemsOpt;
}
