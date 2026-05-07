# web-staging: staging web server.
{ den, ... }:
{
  den.aspects.web-staging = {
    includes = [
      den.aspects.nginx
      den.aspects.hostfile
    ];

    http-backends = {
      addr = "10.0.2.10";
      port = 80;
    };
  };
}
