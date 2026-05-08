# Nginx web server aspect — emits an http-backend quirk.
#
# Each host including this aspect advertises itself as an HTTP backend.
# The quirk is collected by haproxy via pipe.collect.
{ ... }:
{
  den.aspects.nginx = {
    nixos =
      { ... }:
      {
        services.nginx.enable = true;
        services.nginx.virtualHosts.default = {
          default = true;
          root = "/var/www";
        };
      };

    http-backends =
      { host, ... }:
      {
        inherit (host) addr;
        port = host.httpPort;
      };
  };
}
