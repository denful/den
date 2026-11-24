# The per-host user spellings in the users guide: `den.aspects."<user>@<host>"`
# and `den.aspects.<host>.<user>` both reach that user on that host only.
{ denTest, ... }:
let
  two =
    { den, ... }:
    {
      den.default.includes = [ den.provides.define-user ];
      den.hosts.x86_64-linux.igloo.users = {
        tux = { };
        pingu = { };
      };
      den.hosts.x86_64-linux.iceberg.users.tux = { };
    };
  probe = hm: hm.home.sessionVariables.PERHOST or "absent";
in
{
  flake.tests.docs-per-host-user-aspect = {

    test-user-at-host-is-per-user = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        iceberg,
        ...
      }:
      {
        imports = [ two ];
        den.aspects."tux@igloo".homeManager.home.sessionVariables.PERHOST = "tux-on-igloo";
        expr = {
          tux = probe tuxHm;
          pingu = probe pinguHm;
          tuxOnIceberg = probe iceberg.home-manager.users.tux;
        };
        expected = {
          tux = "tux-on-igloo";
          pingu = "absent";
          tuxOnIceberg = "absent";
        };
      }
    );

    test-host-nested-user-key-is-per-user = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        iceberg,
        ...
      }:
      {
        imports = [ two ];
        den.aspects.igloo.tux.homeManager.home.sessionVariables.PERHOST = "from-igloo.tux";
        expr = {
          tux = probe tuxHm;
          pingu = probe pinguHm;
          tuxOnIceberg = probe iceberg.home-manager.users.tux;
        };
        expected = {
          tux = "from-igloo.tux";
          pingu = "absent";
          tuxOnIceberg = "absent";
        };
      }
    );

  };
}
