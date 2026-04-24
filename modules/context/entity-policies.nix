# Defines `policies` on every entity that imports den.schema.conf
# (host, user, home, and user-defined kinds). Allows per-entity-kind
# and per-entity-instance policy activation.
#
# Usage:
#   den.schema.host.policies = [ "host-to-peers" ];
#   den.hosts.x86_64-linux.igloo.policies = [ "host-to-peers" ];
{ lib, ... }:
let
  entityModule = {
    options.policies = lib.mkOption {
      description = ''
        Policy names activated for this entity or entity kind.
        Core policies (_core = true) are always active regardless.
        Policies listed here are activated when this entity is resolved.
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "host-to-peers" ];
    };
  };
in
{
  config.den.schema.conf.imports = [ entityModule ];
}
