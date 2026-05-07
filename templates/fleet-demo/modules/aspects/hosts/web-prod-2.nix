# web-prod-2: production web server.
{ den, ... }:
{
  den.aspects.web-prod-2 = {
    includes = [
      den.aspects.nginx
      den.aspects.hostfile
    ];

    http-backends = {
      addr = "10.0.1.11";
      port = 80;
    };
  };
}
