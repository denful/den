{ den, ... }:
{
  den.aspects.server.includes = with den.aspects; [
    networking
    monitoring
    monitoring.node-exporter
    monitoring.nginx-exporter
    monitoring.alerting
    tailscale
    virtualization
    virtualization.docker
    backup
  ];
}
