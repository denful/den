{ den, lib, ... }:
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
    meta.aspect-chain = [
      "den"
      "provides"
    ];
    __fn =
      {
        class,
        host ? null,
        home ? null,
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
        # Delivered to the host, since this is resolved in a user scope.
        hostDelivery =
          lib.optionalAttrs
            (
              (class == "homeManager" || !builtins.elem class validClasses)
              && host ? class
              # A standalone home binds a host that is not its ancestor: no receiver.
              && home == null
              && builtins.elem host.class validClasses
            )
            {
              includes = [
                {
                  __isPolicy = true;
                  name = "insecure-host(${builtins.concatStringsSep "," allowed-names})";
                  fn =
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = host.class;
                        # Keyed, so the same list from several users lands once.
                        module = {
                          key = "den/insecure-host/${builtins.concatStringsSep "," allowed-names}";
                          permittedInsecurePackages.packages = allowed-names;
                        };
                        receiver = host;
                      })
                    ];
                }
              ];
            };
      in
      classModule // hostDelivery;
    __args = {
      class = true;
      host = true;
      home = true;
    };
  };
in
{
  den.batteries.insecure = {
    inherit description __functor;
  };
}
