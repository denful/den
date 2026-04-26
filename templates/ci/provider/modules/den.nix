{
  inputs,
  den,
  lib,
  ...
}:
{
  imports = [
    inputs.den.flakeModule
    (inputs.den.namespace "provider" true)
  ];

  provider.tools.provides.dev.provides.editors = {
    description = "Editor configurations from provider flake";
    nixos.programs.vim.enable = true;
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.vim ];
      };
  };

  provider.tools.provides.dev.provides.host-stamp = den.lib.parametric {
    includes = [
      (
        { host, ... }:
        {
          nixos.environment.sessionVariables.PROVIDER_HOST = host.name;
        }
      )
    ];
  };

  provider.tools.provides.dev.provides.user-stamp = den.lib.parametric.exactly {
    includes = [
      (
        { host, user, ... }:
        {
          nixos.users.users.${user.userName}.description = "user-of-${host.name}";
        }
      )
    ];
  };

  den.classes.funny.description = "Test class for pipeline verification";

  # A provider entry shared to consumers — provides a self-provider function.
  provider.simple.provides.simple = _: { funny.names = [ "from-provider" ]; };

  # A schema entry that can be shared to consumers.
  provider.schema.entity = {
    options.names = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    config.names = lib.mkDefault [ "provider-entity-schema" ];
  };
}
