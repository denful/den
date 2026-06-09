# In-context `.hasAspect` answers PROJECTED scope membership (what is delivered
# into the active scope), while the registry query stays structural. One symbol,
# overloaded by provenance.
{ denTest, lib, ... }:
{
  flake.tests.projected-hasaspect = {
    test-content-position = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.aspect1.homeManager.programs.atuin.enable = true;
        den.aspects.aspect2 =
          {
            user ? null,
            ...
          }:
          {
            homeManager.config = lib.mkIf (user != null && user.hasAspect den.aspects.aspect1) {
              programs.atuin.daemon.enable = true;
            };
          };
        den.aspects.igloo.provides.tux.includes = [
          den.aspects.aspect1
          den.aspects.aspect2
        ];
        expr = igloo.home-manager.users.tux.programs.atuin.daemon.enable;
        expected = true;
      }
    );

    test-provenance-split = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.aspect1.homeManager.programs.atuin.enable = true;
        den.aspects.aspect2 =
          {
            user ? null,
            ...
          }:
          {
            homeManager.config = lib.mkIf (user != null && user.hasAspect den.aspects.aspect1) {
              programs.atuin.daemon.enable = true;
            };
          };
        den.aspects.igloo.provides.tux.includes = [
          den.aspects.aspect1
          den.aspects.aspect2
        ];
        expr = {
          registry = den.hosts.x86_64-linux.igloo.users.tux.hasAspect den.aspects.aspect1;
          inContext = igloo.home-manager.users.tux.programs.atuin.daemon.enable;
        };
        expected = {
          registry = false;
          inContext = true;
        };
      }
    );

    test-multi-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.aspect1.homeManager.programs.atuin.enable = true;
        den.aspects.aspect2 =
          {
            user ? null,
            ...
          }:
          {
            homeManager.config = lib.mkIf (user != null && user.hasAspect den.aspects.aspect1) {
              programs.atuin.daemon.enable = true;
            };
          };
        den.aspects.igloo = {
          provides.tux.includes = [
            den.aspects.aspect1
            den.aspects.aspect2
          ];
          provides.pingu.includes = [ den.aspects.aspect2 ];
        };
        expr = {
          tux = igloo.home-manager.users.tux.programs.atuin.daemon.enable or false;
          pingu = igloo.home-manager.users.pingu.programs.atuin.daemon.enable or false;
        };
        expected = {
          tux = true;
          pingu = false;
        };
      }
    );

    test-multi-host = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.aspect1.homeManager.programs.atuin.enable = true;
        den.aspects.aspect2 =
          {
            user ? null,
            ...
          }:
          {
            homeManager.config = lib.mkIf (user != null && user.hasAspect den.aspects.aspect1) {
              programs.atuin.daemon.enable = true;
            };
          };
        den.aspects.igloo.provides.tux.includes = [
          den.aspects.aspect1
          den.aspects.aspect2
        ];
        den.aspects.iceberg.provides.tux.includes = [ den.aspects.aspect2 ];
        expr = {
          igloo = igloo.home-manager.users.tux.programs.atuin.daemon.enable or false;
          iceberg = iceberg.home-manager.users.tux.programs.atuin.daemon.enable or false;
        };
        expected = {
          igloo = true;
          iceberg = false;
        };
      }
    );

  };
}
