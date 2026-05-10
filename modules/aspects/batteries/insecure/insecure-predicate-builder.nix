{ lib, ... }:
let
  description = ''
    This is a private aspect always included in den.default.

    It adds a module option that gathers all packages defined
    in den.batteries.insecure usages and declares a
    nixpkgs.config.permittedInsecurePackages for each class.

  '';

  insecureModule =
    { config, ... }@args:
    let
      globalPkgs = args.osConfig.home-manager.useGlobalPkgs or false;
      hasInsecure = config.permittedInsecurePackages.packages != [ ];
    in
    {
      key = "den/insecure-predicate";
      options.permittedInsecurePackages.packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = lib.literalExpression "[ ]";
        default = [ ];
      };
      config.nixpkgs = lib.mkIf (hasInsecure && !globalPkgs) {
        config.permittedInsecurePackages = config.permittedInsecurePackages.packages;
      };
    };

  osAspect =
    { host }:
    {
      name = "insecure-predicate/os";
      ${host.class}.imports = [ insecureModule ];
    };

  userAspect =
    { host, user }:
    {
      name = "insecure-predicate/user";
    }
    // lib.optionalAttrs (lib.elem "homeManager" user.classes) {
      homeManager.imports = [ insecureModule ];
    };

  homeAspect =
    { home }:
    {
      name = "insecure-predicate/home";
      ${home.class}.imports = [ insecureModule ];
    };

  aspect = {
    name = "insecure-predicate";
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
