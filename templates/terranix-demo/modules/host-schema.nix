# Extend the host schema with infrastructure fields used by terranix aspects.
{ lib, den, ... }:
let
  infraFields =
    { ... }:
    {
      options.server-type = lib.mkOption {
        type = lib.types.str;
        default = "cx22";
        description = "Hetzner Cloud server type";
      };
      options.region = lib.mkOption {
        type = lib.types.str;
        default = "fsn1";
        description = "Hetzner Cloud datacenter region";
      };
      options.image = lib.mkOption {
        type = lib.types.str;
        default = "ubuntu-24.04";
        description = "Server image";
      };
    };
in
{
  den.schema.host.imports = [ infraFields ];
}
