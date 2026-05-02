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
      { class, ... }:
      if
        (builtins.elem class [
          "nixos"
          "darwin"
          "homeManager"
        ])
      then
        {
          ${class}.unfree.packages = allowed-names;
        }
      else
        { };
    __args = {
      class = true;
    };
  };
in
{
  den.provides.unfree = {
    inherit description __functor;
  };
}
