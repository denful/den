{ lib, ... }:
{
  # Virtualization with provider sub-aspects for each runtime.
  # Hosts include the providers they want: server gets docker, workstation gets podman.
  den.aspects.virtualization = {
    nixos.virtualisation.oci-containers.backend = lib.mkDefault "docker";

    provides.docker.nixos.virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };

    provides.podman.nixos.virtualisation = {
      podman.enable = true;
      podman.dockerSocket.enable = true;
    };
  };
}
