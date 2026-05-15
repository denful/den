{
  lib,
  config,
  inputs,
  ...
}:
let
  den-lib = inputs.den.lib { inherit inputs lib config; };
  ned = inputs.ned.lib { inherit inputs; };
  pipe = inputs.pipe.lib;
  bend = inputs.bend.lib;

  import-tree =
    inputs.import-tree # compose custom import-tree
      (it: it.addScoped { inherit ned pipe bend; }) # other libs
      (it: it.addScoped den-lib) # all of den.lib.* in scope including __findFile
  ;
in
{
  imports = [ (import-tree ./modules) ];
}
