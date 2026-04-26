{ denTest, ... }:
{
  flake.tests.hm-host-isolation = {

    test-hm-host-owned-config-not-applied-without-hm-users = denTest (
      { den, funnyNames, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.stages.hm-host.funny.names = [ "hm-host-owned" ];
        den.stages.hm-host.includes = [ ];

        expr = funnyNames (den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; });
        expected = [ ];
      }
    );

    test-hm-host-includes-not-applied-without-hm-users = denTest (
      { den, funnyNames, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.stages.hm-host.includes = [
          { funny.names = [ "hm-host-include" ]; }
        ];

        expr = funnyNames (den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; });
        expected = [ ];
      }
    );

  };
}
