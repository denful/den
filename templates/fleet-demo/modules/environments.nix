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
  environmentType = den.lib.schema.mkInstanceType {
    strict = false;
    extraModules = [
      (
        { name, config, ... }:
        {
          config._module.args.environment = config;
          options = {
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
      )
    ];
  } den.schema.environment;

  # The environment is a fact, so user assignment can read it before any host
  # is resolved; the host field follows it.
  hostFacts = {
    options.environment = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Environment this host belongs to";
    };
  };

  # Extend host schema with environment + networking fields.
  extendHostSchema =
    { config, ... }:
    {
      options.environment = lib.mkOption {
        type = lib.types.str;
        default = config.facts.environment;
        description = "Environment this host belongs to (from `facts.environment`)";
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
  config.den.schema.host.facts = [ hostFacts ];

  config.fleet.environments = {
    prod = {
      domain-name = "example.com";
    };
    staging = {
      domain-name = "staging.example.com";
    };
  };
}
