# User-defined environment entity.
#
# Demonstrates that den entity types can be defined entirely in user
# flakes — no framework changes required. The environment type extends
# den.schema.environment and registers instances via fleet.environments.
{
  lib,
  den,
  ...
}:
let
  environmentType = lib.types.submodule (
    { name, config, ... }:
    {
      freeformType = lib.types.attrsOf lib.types.anything;
      imports = [ den.schema.environment ];
      config._module.args.environment = config;
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Environment name";
        };
        domain-name = lib.mkOption {
          type = lib.types.str;
          default = "local";
          description = "Domain name for this environment";
        };
        aspect = lib.mkOption {
          type = lib.types.raw;
          default = if den.aspects ? ${name} then den.aspects.${name} else { };
          defaultText = "den.aspects.<name>";
          description = "Aspect that configures this environment";
        };
      };
    }
  );

  # Extend host schema with environment + networking fields.
  extendHostSchema =
    { ... }:
    {
      options.environment = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Environment this host belongs to";
      };
      options.addr = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Primary IP address of this host";
      };
      options.httpPort = lib.mkOption {
        type = lib.types.port;
        default = 80;
        description = "HTTP port for this host's web server";
      };
    };
in
{
  options.fleet.environments = lib.mkOption {
    type = lib.types.attrsOf environmentType;
    default = { };
    description = "Environment definitions";
  };

  config.den.schema.host.imports = [ extendHostSchema ];

  config.fleet.environments = {
    prod = {
      domain-name = "example.com";
    };
    staging = {
      domain-name = "staging.example.com";
    };
  };
}
