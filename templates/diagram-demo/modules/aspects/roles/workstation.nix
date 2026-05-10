{ den, ... }:
{
  den.aspects.workstation.includes = with den.aspects; [
    networking
    tailscale
    desktop
    virtualization
    virtualization.podman
  ];
}
