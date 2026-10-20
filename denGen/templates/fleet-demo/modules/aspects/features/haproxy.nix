# Haproxy aspect — consumes http-backends from pipe.collect.
#
# Generates haproxy backend configuration from all peer hosts'
# http-backend entries in the same environment.
{ lib, ... }:
{
  den.aspects.haproxy = {
    nixos =
      { http-backends, lib, ... }:
      let
        backendLines = lib.imap1 (
          i: b: "  server backend${toString i} ${b.addr}:${toString b.port} check"
        ) http-backends;
      in
      {
        services.haproxy.enable = true;
        services.haproxy.config = lib.concatStringsSep "\n" (
          [
            "frontend http-in"
            "  bind *:80"
            "  default_backend webservers"
            ""
            "backend webservers"
            "  balance roundrobin"
          ]
          ++ backendLines
        );
      };
  };
}
