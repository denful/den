# Hostfile aspect — consumes host-addrs from pipe.collect.
#
# Generates /etc/hosts entries from all peer hosts in the same environment.
{ lib, ... }:
{
  den.aspects.hostfile = {
    nixos =
      { host-addrs, lib, ... }:
      {
        networking.extraHosts = lib.concatMapStringsSep "\n" (
          entry: "${entry.addr} ${entry.hostname}"
        ) host-addrs;
      };

    host-addrs =
      { host, config, ... }:
      {
        hostname = config.networking.hostName;
        addr = host.addr;
      };
  };
}
