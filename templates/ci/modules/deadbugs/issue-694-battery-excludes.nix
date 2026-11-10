# An argument battery's instances take `den.batteries.<name>`'s identity, so
# excluding the battery removes every instance it reaches: the host's own,
# or a user's from that user.
{ denTest, lib, ... }:
let
  two = {
    den.hosts.x86_64-linux.igloo.users = {
      tux = { };
      pingu = { };
    };
  };
  unfree = igloo: igloo.unfree.packages;
  insecure = igloo: igloo.permittedInsecurePackages.packages;
  autologin = svc: lib.any (lib.hasInfix "--autologin") (svc.serviceConfig.ExecStart or [ ]);
  tty = igloo: autologin (igloo.systemd.services."getty@tty1" or { });
  vm = igloo: autologin (igloo.virtualisation.vmVariant.systemd.services."getty@tty1" or { });
in
{
  flake.tests.battery-excludes = {
    test-host-excludes-unfree = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.igloo.includes = [
          (den.batteries.unfree [ "z1" ])
          (den.batteries.unfree [
            "z2"
            "z3"
          ])
        ];
        den.aspects.igloo.excludes = [ den.batteries.unfree ];
        expr = unfree igloo;
        expected = [ ];
      }
    );
    test-user-excludes-unfree = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.tux.includes = [ (den.batteries.unfree [ "z1" ]) ];
        den.aspects.tux.excludes = [ den.batteries.unfree ];
        expr = unfree igloo;
        expected = [ ];
      }
    );
    test-host-excludes-insecure = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.igloo.includes = [ (den.batteries.insecure [ "i2" ]) ];
        den.aspects.igloo.excludes = [ den.batteries.insecure ];
        expr = insecure igloo;
        expected = [ ];
      }
    );
    test-user-excludes-insecure = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.tux.includes = [ (den.batteries.insecure [ "i1" ]) ];
        den.aspects.tux.excludes = [ den.batteries.insecure ];
        expr = insecure igloo;
        expected = [ ];
      }
    );
    test-host-excludes-tty-autologin = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.igloo.includes = [ (den.batteries.tty-autologin "tux") ];
        den.aspects.igloo.excludes = [ den.batteries.tty-autologin ];
        expr = tty igloo;
        expected = false;
      }
    );
    test-user-excludes-tty-autologin = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.tux.includes = [ (den.batteries.tty-autologin "tux") ];
        den.aspects.tux.excludes = [ den.batteries.tty-autologin ];
        expr = tty igloo;
        expected = false;
      }
    );
    test-host-excludes-vm-autologin = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.igloo.includes = [ (den.batteries.vm-autologin "tux") ];
        den.aspects.igloo.excludes = [ den.batteries.vm-autologin ];
        expr = vm igloo;
        expected = false;
      }
    );
    test-user-excludes-vm-autologin = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.tux.includes = [ (den.batteries.vm-autologin "tux") ];
        den.aspects.tux.excludes = [ den.batteries.vm-autologin ];
        expr = vm igloo;
        expected = false;
      }
    );
    # Excluding one argument set leaves the battery's other sets.
    test-host-excludes-one-set = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.igloo.includes = [
          (den.batteries.unfree [ "z1" ])
          (den.batteries.unfree [ "z2" ])
        ];
        den.aspects.igloo.excludes = [ (den.batteries.unfree [ "z1" ]) ];
        expr = unfree igloo;
        expected = [ "z2" ];
      }
    );
    # Controls: excluding one battery leaves the others landing.
    test-control-unexcluded-lands = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.tux.includes = [ (den.batteries.unfree [ "z1" ]) ];
        den.aspects.igloo.includes = [
          (den.batteries.insecure [ "i2" ])
          (den.batteries.tty-autologin "tux")
          (den.batteries.vm-autologin "tux")
        ];
        den.aspects.igloo.excludes = [ den.batteries.user-aspects ];
        expr = {
          unfree = unfree igloo;
          insecure = insecure igloo;
          tty = tty igloo;
          vm = vm igloo;
        };
        expected = {
          unfree = [ "z1" ];
          insecure = [ "i2" ];
          tty = true;
          vm = true;
        };
      }
    );
    test-control-other-sets-land = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.aspects.tux.includes = [ (den.batteries.unfree [ "z1" ]) ];
        den.aspects.tux.excludes = [ den.batteries.insecure ];
        expr = unfree igloo;
        expected = [ "z1" ];
      }
    );
  };
}
