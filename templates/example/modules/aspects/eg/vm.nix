{ eg, ... }:
{
  eg.vm = {
    gui.includes = [
      eg.vm
      eg.vm-bootable.gui
      eg.xfce-desktop
    ];

    tui.includes = [
      eg.vm
      eg.vm-bootable.tui
    ];
  };
}
