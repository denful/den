let
  description = ''
    A class generic aspect that enables unfree packages by name.

    Works for any class (nixos/darwin/homeManager,etc) on any host/user/home context.

    ## Usage

      den.aspects.my-laptop.includes = [ (den.provides.unfree [ "example-unfree-package" ]) ];

    It will dynamically provide a module for each class when accessed.
  '';

  __functor = _self: allowed-names: {
    name = "unfree(${builtins.concatStringsSep "," allowed-names})";
    meta.provider = [
      "den"
      "provides"
    ];
    __fn =
      { class, ... }@args:
      let
        # At user scope, emit to the user's primary class (e.g. homeManager)
        # instead of the pipeline class (nixos). The old sub-pipeline system
        # set class per-entity; the unified pipeline uses one root class.
        targetClass =
          if args ? user then builtins.head ((args.user.classes or [ ]) ++ [ class ]) else class;
      in
      if
        (builtins.elem targetClass [
          "nixos"
          "darwin"
          "homeManager"
        ])
      then
        {
          ${targetClass}.unfree.packages = allowed-names;
        }
      else
        { };
    __args = {
      class = true;
      user = true;
    };
  };
in
{
  den.provides.unfree = {
    inherit description __functor;
  };
}
