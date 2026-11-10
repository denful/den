{ den, lib, ... }:
let
  description = ''
    A class generic aspect that enables unfree packages by name.

    Works for any class (nixos/darwin/homeManager,etc) on any host/user/home context.

    ## Usage

      den.aspects.my-laptop.includes = [ (den.batteries.unfree [ "example-unfree-package" ]) ];

    It will dynamically provide a module for each class when accessed.
  '';

  __functor = _self: allowed-names: {
    name = "unfree(${den.lib.argsName.setOf allowed-names})";
    meta.aspect-chain = [
      "den"
      "batteries"
      "unfree"
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
          ${class}.unfree.packages = allowed-names;
        };
        # When resolving for homeManager or a non-module-system class (e.g.
        # "user"), also emit to the host's OS class.  This ensures
        # nixpkgs.config.allowUnfreePredicate covers these packages:
        #   - homeManager + useGlobalPkgs = true → OS-level predicate needed
        #   - "user" class (no HM) → only the host's OS config exists
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
                  name = "unfree-host(${den.lib.argsName.setOf allowed-names})";
                  fn =
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = host.class;
                        # Keyed, so the same list from several users lands once.
                        module = {
                          key = "den/unfree-host/${den.lib.argsName.setOf allowed-names}";
                          unfree.packages = allowed-names;
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
  # Named, so `excludes = [ den.batteries.unfree ]` reaches every instance.
  den.batteries.unfree = {
    name = "unfree";
    meta.aspect-chain = [
      "den"
      "batteries"
    ];
    inherit description __functor;
  };
}
