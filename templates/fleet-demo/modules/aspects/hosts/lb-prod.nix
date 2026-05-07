# lb-prod: production load balancer.
# Collects http-backends from prod peers via pipe.collect,
# generates haproxy config and /etc/hosts.
{ den, ... }:
{
  den.aspects.lb-prod = {
    includes = [
      den.aspects.haproxy
      den.aspects.hostfile
    ];
    # lb doesn't serve HTTP itself — no http-backends quirk.
    # host-addrs emitted by emit-host-addr policy (reads host.addr).
  };
}
