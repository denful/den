# Devbox host: dual-role hybrid with multi-user support.
#
# Demonstrates five patterns:
#   1. <den/primary-user> — angle-bracket dynamic include
#   2. Dual role — workstation + server on one host
#   3. exclude — remove tailscale and docker (podman from workstation wins)
#   4. substitute — swap regreet greeter for gdm
#   5. Multi-user — alice (hyprland) + bob (gnome) on same host
{ den, ... }:
{
  den.aspects.devbox = {
    includes = [
      den.batteries.primary-user
      den.aspects.workstation
      den.aspects.server
    ];
    meta.handleWith = [
      # No tailscale on devbox
      (den.lib.aspects.fx.constraints.exclude den.aspects.tailscale)
      # Prefer podman over docker (podman comes from workstation)
      (den.lib.aspects.fx.constraints.exclude den.aspects.virtualization.docker)
      # Use gdm instead of the default regreet greeter
      (den.lib.aspects.fx.constraints.substitute den.aspects.regreet den.aspects.gdm)
    ];
  };
}
