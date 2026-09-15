{
  inputs,
  config,
  lib,
  den,
  ...
}:
let
  inherit (import ./_types.nix { inherit lib den; })
    strOpt
    lookupAspect
    lookupAspectBy
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

  innerType = lib.types.attrsOf systemType;

  hostsOption = lib.mkOption {
    description = "den hosts definition";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.attrsOf (lib.types.submodule { freeformType = deepMergeAttrs; });
    apply =
      raw:
      let
        normalized = preprocessHosts raw;
      in
      innerType.merge
        [ "den" "hosts" ]
        [
          {
            file = "<den.hosts>";
            value = normalized;
          }
        ];
  };

  systemType = lib.types.submodule (
    { name, ... }:
    {
      freeformType = lib.types.attrsOf (hostType name);
    }
  );

  hostType =
    system:
    schemaLib.mkInstanceType den.schema.host {
      strict = false;
      extraModules = [
        (resolvedCtxModule "host")
        (
          { config, ... }:
          {
            options = {
              hostName = strOpt "Network hostname" config.name;
              system = strOpt "platform system" system;
              class = strOpt "os-configuration nix class for host" (
                if lib.hasSuffix "darwin" config.system then "darwin" else "nixos"
              );
              aspect = lib.mkOption {
                description = "Aspect that configures this host.";
                type = lib.types.raw; # no merging
                defaultText = "den.aspects.<name>";
                default = lookupAspect den config;
              };
              description = strOpt "host description" "${config.class}.${config.hostName}@${config.system}";
              users = lib.mkOption {
                description = "user accounts";
                default = { };
                defaultText = lib.literalExpression "{ }";
                type = lib.types.attrsOf (userType config);
              };
              instantiate = lib.mkOption {
                description = ''
                  Function used to instantiate the OS configuration.

                  Depending on class, defaults to:
                  `darwin`: inputs.darwin.lib.darwinSystem
                  `nixos`:  inputs.nixpkgs.lib.nixosSystem
                  `systemManager`: inputs.system-manager.lib.makeSystemConfig

                  Set explicitly if you need:

                  - a custom input name, eg, nixos-unstable.
                  - adding specialArgs when absolutely required.
                '';
                example = lib.literalExpression "inputs.nixpkgs.lib.nixosSystem";
                type = lib.types.raw;
                defaultText = lib.literalExpression "inputs.nixpkgs.lib.nixosSystem";
                default =
                  {
                    nixos = inputs.nixpkgs.lib.nixosSystem;
                    darwin = inputs.darwin.lib.darwinSystem;
                    systemManager = inputs.system-manager.lib.makeSystemConfig;
                  }
                  .${config.class};
              };
              intoAttr = lib.mkOption {
                description = ''
                  Flake attr where to add the named result of this configuration.
                  flake.<intoAttr>.<name>

                  Depending on class, defaults to:
                  `darwin`: darwinConfigurations
                  `nixos`:  nixosConfigurations
                  `systemManager`: systemConfigs
                '';
                example = lib.literalExpression ''[  "nixosConfigurations" hostName ]'';
                type = lib.types.listOf lib.types.str;
                defaultText = lib.literalExpression ''[  "nixosConfigurations" hostName ]'';
                default =
                  {
                    nixos = [
                      "nixosConfigurations"
                      config.name
                    ];
                    darwin = [
                      "darwinConfigurations"
                      config.name
                    ];
                    systemManager = [
                      "systemConfigs"
                      config.name
                    ];
                  }
                  .${config.class};
              };
              mainModule = mainModuleOption den config;
              __resolveResult = resolveResultOption den config;
              __pathSetByScope = pathSetByScopeOption den "host" config;
            };
          }
        )
      ];
    };

  userType =
    host:
    schemaLib.mkInstanceType den.schema.user {
      strict = false;
      extraModules = [
        (resolvedCtxModule "user")
        (
          { config, ... }:
          {
            config._module.args.host = host;
            options = {
              userName = strOpt "user account name" config.name;
              classes = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "home management nix classes";
                defaultText = lib.literalExpression ''[ "user" ]'';
                default = [ "user" ];
              };
              aspect = lib.mkOption {
                description = "Aspect that configures this user.";
                type = lib.types.raw; # no merging
                defaultText = "den.aspects.<name>@<host> or den.aspects.<name>";
                # Host-qualified first, so one user can be configured per host
                # without the bare aspect having to branch on `host.name`. Same
                # two candidates a standalone home asks for, so a user's aspect
                # resolves identically whether they are a host user or a home.
                default = lookupAspectBy den [
                  "${config.name}@${host.name}"
                  config.name
                ];
              };
              host = lib.mkOption {
                default = host;
                defaultText = lib.literalExpression "host";
              };
            };
          }
        )
      ];
    };
in
{
  inherit hostsOption;
}
