# web-prod-2: production web server.
{ den, ... }:
{
  den.aspects.web-prod-2 = {
    includes = [
      den.aspects.nginx
      den.aspects.hostfile
    ];
  };
}
