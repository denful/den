# web-staging: staging web server.
{ den, ... }:
{
  den.aspects.web-staging = {
    includes = [
      den.aspects.nginx
      den.aspects.hostfile
    ];
  };
}
