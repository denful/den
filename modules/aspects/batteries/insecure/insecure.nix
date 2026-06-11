{ lib, ... }:
let
  description = ''
    A class generic aspect that enables insecure packages by name and version.

    Works for any class (nixos/darwin/homeManager,etc) on any host/user/home context.

    ## Usage

      den.aspects.my-laptop.includes = [ (den.batteries.insecure [ "example-insecure-package-1.0.0" ]) ];

    It will dynamically provide a module for each class when accessed.
  '';

  __functor = _self: allowed-names: {
    name = "insecure(${builtins.concatStringsSep "," allowed-names})";
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
          ${class}.permittedInsecurePackages.packages = allowed-names;
        };
        # When resolving for homeManager or a non-module-system class (e.g.
        # "user"), also emit to the host's OS class so
        # nixpkgs.config.permittedInsecurePackages covers these packages.
        hostModule = lib.optionalAttrs (
          (class == "homeManager" || !builtins.elem class validClasses)
          && host ? class
          && builtins.elem host.class validClasses
        ) { ${host.class}.permittedInsecurePackages.packages = allowed-names; };
      in
      classModule // hostModule;
    __args = {
      class = true;
      host = true;
    };
  };
in
{
  den.batteries.insecure = {
    inherit description __functor;
  };
}
