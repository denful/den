# web-1: production web server.
{ ... }:
{
  den.aspects.web-1 = {
    nixos =
      { ... }:
      {
        services.nginx.enable = true;
        services.nginx.virtualHosts.default = {
          default = true;
          root = "/var/www";
        };
      };
  };
}
