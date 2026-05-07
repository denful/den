# web-prod-1: production web server.
# Emits http-backends quirk (collected by lb-prod via pipe.collect).
{ den, ... }:
{
  den.aspects.web-prod-1 = {
    includes = [
      den.aspects.nginx
      den.aspects.hostfile
    ];

    # Static quirk — addr/port from host schema options.
    # Collected by peers via pipe.collect.
    http-backends = {
      addr = "10.0.1.10";
      port = 80;
    };
  };
}
