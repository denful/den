{
  inputs,
  config,
  lib,
  den,
  ...
}@top:
let
  inherit (import ./_types.nix { inherit lib den; })
    strOpt
    lookupAspect
    deepMergeAttrs
    mainModuleOption
    resolveResultOption
    pathSetByScopeOption
    resolvedCtxModule
    preprocessHosts
    ;

  # Entity instances are gen-schema instances: mkInstanceType injects name,
  # strict/freeform, _module.args.<kind>, and schema-owned id_hash (identity).
  schemaLib = den.lib.schema;

  innerType = lib.types.attrsOf homeSystemType;

  homesOption = lib.mkOption {
    description = "den standalone home-manager configurations";
    default = { };
    type = lib.types.attrsOf (lib.types.submodule { freeformType = deepMergeAttrs; });
    apply =
      raw:
      let
        normalized = preprocessHosts raw;
      in
      innerType.merge
        [ "den" "homes" ]
        [
          {
            file = "<den.homes>";
            value = normalized;
          }
        ];
  };

  homeSystemType = lib.types.submodule (
    { name, ... }:
    {
      freeformType = lib.types.attrsOf (homeType name);
    }
  );

  homeType =
    system:
    schemaLib.mkInstanceType den.schema.home {
      strict = false;
      extraModules = [
        (resolvedCtxModule "home")
        (
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
            # The synthetic host stays classless: `host ? class` is what keeps
            # OS-class routing (os-to-host, user-to-host, hostname, unfree, …)
            # inert for a host that was never declared. It does carry `system`,
            # which the home knows for certain and which host-keyed content needs
            # to compute platform-dependent values (e.g. define-user's home dir).
            hostCtx =
              if hostByName != null then
                hostByName
              else if nameWithHost then
                {
                  name = hostName;
                  inherit system;
                }
              else
                null;

            # A standalone home always names its user, whether or not a declared
            # host can resolve one. Binding it from the home is what lets a
            # `{ user, ... }` class module resolve at all: without it
            # wrapFunctionModule takes the missingDenArgNames path and the whole
            # class block is dropped — silently, since the lib.warn it attaches
            # rides on the discarded module and is never forced.
            #
            # A declared host still wins, so a real user keeps its full record
            # (classes, aspect, host). The synthetic one is identity-only; OS
            # batteries do not act on it because they gate on `host ? class`,
            # which no standalone home satisfies.
            userCtx =
              if userByName != null then
                userByName
              else
                {
                  name = userName;
                  userName = userName;
                  classes = [ config.class ];
                };

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
            # mkInstanceType defaults name to the registry key (e.g. "tux@igloo");
            # den's name is the bare user name, so identity/description stay stable.
            # That also makes `name` non-unique across homes (two `user@host` homes
            # on one system share it), so the registry key is kept as the scope
            # identity — see __scopeName in ./_types.nix.
            config.name = lib.mkForce userName;
            config.__scopeName = name;
            config._identity.keys = [
              "__scopeName"
              "system"
            ];
            config._module.args.host = hostCtx;
            config._module.args.user = userCtx;
            options = {

              userName = strOpt "user account name" userName;
              hostName = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = hostName;
                description = "host name (null for unbound standalone homes)";
              };
              user = lib.mkOption {
                default = userCtx;
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
              __pathSetByScope = pathSetByScopeOption den "home" config;
            };
          }
        )
      ];
    };
in
{
  inherit homesOption;
}
