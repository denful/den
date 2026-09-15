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

  # Chain segments state each child's position under "unfree-predicate"
  # explicitly rather than letting the name carry it — a name can never
  # double-encode an ancestor that's already named as its own chain segment.
  osAspect =
    { host }:
    {
      name = "os";
      meta.aspect-chain = [ "unfree-predicate" ];
    }
    # A synthetic host identity (from a `user@host` home with no declared host)
    # has no class output, so there is nothing to import into. Guard like
    # homeAspect already does.
    // lib.optionalAttrs (host ? class) {
      ${host.class}.imports = [ unfreeModule ];
    };

  userAspect =
    { host, user }:
    {
      name = "user";
      meta.aspect-chain = [ "unfree-predicate" ];
    }
    // lib.optionalAttrs (lib.elem "homeManager" user.classes) {
      homeManager.imports = [ unfreeModule ];
    };

  homeAspect =
    { home }:
    {
      name = "home";
      meta.aspect-chain = [ "unfree-predicate" ];
    }
    // lib.optionalAttrs (home ? class) {
      ${home.class}.imports = [ unfreeModule ];
    };

  aspect = {
    name = "unfree-predicate";
    # Stated explicitly, not left to fill from the walk: this is included
    # from den.default, and without its own chain it would inherit
    # den.default's position instead of staying a root.
    meta.aspect-chain = [ ];
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
