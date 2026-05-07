# web-prod-1: production web server.
# Emits http-backends quirk (collected by lb-prod via pipe.collect).
{ den, ... }:
{
  den.aspects.web-prod-1 = {
    includes = [
      den.aspects.nginx
      den.aspects.hostfile
    ];

    http-backends =
      { host, ... }:
      {
        inherit (host) addr;
        port = host.httpPort;
      };

    host-addrs = {
      hostname = "web-prod-1";
      addr = "10.0.1.10";
    };
  };
}
