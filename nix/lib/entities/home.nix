{
  inputs,
  config,
  lib,
  den,
  ...
}@top:
let
  inherit (import ./_types.nix { inherit lib; })
    strOpt
    lookupAspect
    mainModuleOption
    resolveResultOption
    pathSetByScopeOption
    ;

  homesOption = lib.mkOption {
    description = "den standalone home-manager configurations";
    default = { };
    type = lib.types.attrsOf homeSystemType;
  };

  homeSystemType = lib.types.submodule (
    { name, ... }:
    {
      freeformType = lib.types.attrsOf (homeType name);
    }
  );

  homeType =
    system:
    lib.types.submodule (
      { name, config, ... }:
      let
        parts = builtins.split "@" name;
        nameWithHost = builtins.length parts > 1;
        userName = lib.head parts;
        hostName = if nameWithHost then lib.last parts else null;
        hostByName = if hostName != null then den.hosts.${system}.${hostName} or null else null;
        userByName = if hostByName != null then hostByName.users.${userName} or null else null;

        # A home named `user@host` carries a host identity even when that host
        # isn't declared in `den.hosts`. Synthesize a minimal `{ name = ...; }`
        # so host-keyed provides/policies (which match on `host.name`) resolve
        # for an otherwise-standalone home — without instantiating a real host
        # entity, which would pull in its platform builder (e.g. nix-darwin).
        # A declared host always wins and remains the only thing that wires
        # `osConfig`.
        #
        # Only `host` is synthesized, never `user`: a synthetic host alone fires
        # `{ host }`-keyed policies (gated on `host ? class` so OS-class routing
        # stays inert for a classless synthetic host), while `{ host, user }`-keyed
        # OS batteries (define-user, user-to-host, …) keep their existing
        # null-user gating and fall back to their home-scope path.
        hostCtx =
          if hostByName != null then
            hostByName
          else if nameWithHost then
            { name = hostName; }
          else
            null;

        homeManagerConfiguration =
          if nameWithHost && hostByName != null then
            { pkgs, modules }:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs modules;
              extraSpecialArgs.osConfig = lib.attrByPath (
                [ "flake" ] ++ hostByName.intoAttr ++ [ "config" ]
              ) null top.config;
            }
          else
            inputs.home-manager.lib.homeManagerConfiguration;
      in
      {
        freeformType = lib.types.attrsOf lib.types.anything;
        imports = [ den.schema.home ];
        config._module.args.home = config;
        config._module.args.host = hostCtx;
        config._module.args.user = userByName;
        options = {
          name = strOpt "home configuration name" userName;
          userName = strOpt "user account name" userName;
          hostName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = hostName;
            description = "host name (null for unbound standalone homes)";
          };
          user = lib.mkOption {
            default = userByName;
            defaultText = lib.literalExpression "user";
          };
          host = lib.mkOption {
            default = hostCtx;
            defaultText = lib.literalExpression "host";
          };
          system = strOpt "platform system" system;
          class = strOpt "home management nix class" "homeManager";
          aspect = lib.mkOption {
            description = "Aspect that configures this home.";
            type = lib.types.raw; # no merging
            defaultText = "den.aspects.<name>";
            default = lookupAspect den config;
          };
          description = strOpt "home description" "home.${config.name}@${config.system}";
          pkgs = lib.mkOption {
            description = ''
              nixpkgs instance used to build the home configuration.
            '';
            example = lib.literalExpression ''inputs.nixpkgs.legacyPackages.''${home.system}'';
            type = lib.types.raw;
            defaultText = lib.literalExpression ''inputs.nixpkgs.legacyPackages.''${home.system}'';
            default = inputs.nixpkgs.legacyPackages.${config.system};
          };
          instantiate = lib.mkOption {
            description = ''
              Function used to instantiate the home configuration.

              Depending on class, defaults to:
              `homeManager`: inputs.home-manager.lib.homeManagerConfiguration

              Set explicitly if you need:

              - a custom input name, eg, home-manager-unstable.
              - adding extraSpecialArgs when absolutely required.
            '';
            example = lib.literalExpression "inputs.home-manager.lib.homeManagerConfiguration";
            type = lib.types.raw;
            defaultText = lib.literalExpression "inputs.home-manager.lib.homeManagerConfiguration";
            default =
              {
                homeManager = homeManagerConfiguration;
              }
              .${config.class};
          };
          intoAttr = lib.mkOption {
            description = ''
              Flake attr where to add the named result of this configuration.
              flake.<intoAttr>.<name>

              Depending on class, defaults to:
              `homeManager`: homeConfigurations
            '';
            example = lib.literalExpression ''[  "homeConfigurations" userName ]'';
            type = lib.types.listOf lib.types.str;
            defaultText = lib.literalExpression ''[  "homeConfigurations" userName ]'';
            default =
              {
                homeManager = [
                  "homeConfigurations"
                  name
                ];
              }
              .${config.class};
          };
          mainModule = mainModuleOption den config;
          __resolveResult = resolveResultOption den config;
          __pathSetByScope = pathSetByScopeOption den config;
        };
      }
    );
in
{
  inherit homesOption;
}
