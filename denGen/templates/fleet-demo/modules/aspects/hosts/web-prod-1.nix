# web-prod-1: production web server.
# Emits http-backends quirk (collected by lb-prod via pipe.collect).
{ den, ... }:
{
  den.aspects.web-prod-1 = {
    includes = [
      den.aspects.nginx
      den.aspects.hostfile
    ];
  };
}
