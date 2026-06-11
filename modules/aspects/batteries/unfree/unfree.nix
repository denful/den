{ lib, ... }:
let
  description = ''
    A class generic aspect that enables unfree packages by name.

    Works for any class (nixos/darwin/homeManager,etc) on any host/user/home context.

    ## Usage

      den.aspects.my-laptop.includes = [ (den.batteries.unfree [ "example-unfree-package" ]) ];

    It will dynamically provide a module for each class when accessed.
  '';

  __functor = _self: allowed-names: {
    name = "unfree(${builtins.concatStringsSep "," allowed-names})";
    meta.provider = [
      "den"
      "provides"
    ];
    __fn =
      {
        class,
        host ? null,
        ...
      }:
      let
        validClasses = [
          "nixos"
          "darwin"
          "homeManager"
        ];
        classModule = lib.optionalAttrs (builtins.elem class validClasses) {
          ${class}.unfree.packages = allowed-names;
        };
        # When resolving for homeManager or a non-module-system class (e.g.
        # "user"), also emit to the host's OS class.  This ensures
        # nixpkgs.config.allowUnfreePredicate covers these packages:
        #   - homeManager + useGlobalPkgs = true → OS-level predicate needed
        #   - "user" class (no HM) → only the host's OS config exists
        hostModule = lib.optionalAttrs (
          (class == "homeManager" || !builtins.elem class validClasses)
          && host ? class
          && builtins.elem host.class validClasses
        ) { ${host.class}.unfree.packages = allowed-names; };
      in
      classModule // hostModule;
    __args = {
      class = true;
      host = true;
    };
  };
in
{
  den.batteries.unfree = {
    inherit description __functor;
  };
}
