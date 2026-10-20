# Pipe declarations and collection policies.
#
# Declares two pipes:
#   http-backends  — backend addresses collected by haproxy
#   host-addrs     — host IP/name pairs collected for /etc/hosts generation
{ den, lib, ... }:
let
  inherit (den.lib.policy) pipe;
in
{
  # Quirk declarations — establishes these keys as pipes, not classes.
  den.quirks.http-backends = {
    description = "HTTP backend addresses for load balancer aggregation";
  };

  den.quirks.host-addrs = {
    description = "Host address entries for /etc/hosts generation";
  };

  # Every host collects http-backends from peers.
  den.policies.collect-backends =
    { host, ... }:
    [
      (pipe.from "http-backends" [
        (pipe.collect ({ host, ... }: true))
      ])
    ];

  # Every host collects host-addrs from peers for /etc/hosts.
  den.policies.collect-host-addrs =
    { host, ... }:
    [
      (pipe.from "host-addrs" [
        (pipe.collect ({ host, ... }: true))
      ])
    ];

  den.schema.host.includes = [
    den.policies.collect-backends
    den.policies.collect-host-addrs
  ];
}
