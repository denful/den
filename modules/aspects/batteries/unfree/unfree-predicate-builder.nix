{ lib, ... }:
let
  description = ''
    This is a private aspect always included in den.default.

    It adds a module option that gathers all packages defined
    in den.batteries.unfree usages and declares a
    nixpkgs.config.allowUnfreePredicate for each class.

  '';

  unfreeModule =
    { config, ... }@args:
    let
      globalPkgs = args.osConfig.home-manager.useGlobalPkgs or false;
      hasUnfree = config.unfree.packages != [ ];
    in
    {
      key = "den/unfree-predicate";
      options.unfree.packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = lib.literalExpression "[ ]";
        default = [ ];
      };
      config.nixpkgs = lib.mkIf (hasUnfree && !globalPkgs) {
        config.allowUnfreePredicate = (pkg: builtins.elem (lib.getName pkg) config.unfree.packages);
      };
    };

  osAspect =
    { host }:
    {
      name = "unfree-predicate/os";
      ${host.class}.imports = [ unfreeModule ];
    };

  userAspect =
    { host, user }:
    {
      name = "unfree-predicate/user";
    }
    // lib.optionalAttrs (lib.elem "homeManager" user.classes) {
      homeManager.imports = [ unfreeModule ];
    };

  homeAspect =
    { home }:
    {
      name = "unfree-predicate/home";
      ${home.class}.imports = [ unfreeModule ];
    };

  aspect = {
    name = "unfree-predicate";
    inherit description;
    includes = [
      osAspect
      userAspect
      homeAspect
    ];
  };
in
{
  den.default.includes = [ aspect ];
}
