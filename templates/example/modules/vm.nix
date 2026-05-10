# enables `nix run .#vm`. it is very useful to have a VM
# you can edit your config and launch the VM to test stuff
# instead of having to reboot each time.
{ inputs, eg, ... }:
{

  den.aspects.igloo.includes = [
    eg.vm.gui
    # eg.vm.tui
  ];

  perSystem =
    { pkgs, ... }:
    {
      packages.vm = pkgs.writeShellApplication {
        name = "vm";
        text = ''
          ${inputs.self.nixosConfigurations.igloo.config.system.build.vm}/bin/run-igloo-vm "$@"
        '';
      };
    };
}
