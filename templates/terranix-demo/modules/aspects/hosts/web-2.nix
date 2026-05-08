# web-2: production web server (different region).
{ ... }:
{
  den.aspects.web-2 = {
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
