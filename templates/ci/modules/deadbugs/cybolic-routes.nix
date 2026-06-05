{ denTest, ... }:
{

  # See den#165, https://github.com/Cybolic/nix-den-bug-double-import-routes/tree/3cccc7c
  flake.tests.deadbugs-cybolic-routes = {

    test-has-no-dups = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.routes =
          let
            inherit (den.lib) parametric;
            # eg, `<user>.provides.<host>` and `<host>.provides.<user>`
            mutual = from: to: from.aspect.provides.${to.aspect.name} or { };

            routes =
              { host, user, ... }@ctx:
              parametric.fixedTo ctx {
                includes = [
                  (mutual user host)
                  (mutual host user)
                ];
              };
          in
          routes;

        den.default.includes = [ den.aspects.routes ];

        den.aspects.igloo.provides.tux = den.lib.parametric {
          includes = [ den.aspects.testing ];
        };

        den.aspects.testing =
          { user, ... }:
          {
            homeManager =
              { pkgs, ... }:
              {
                home.packages = [ pkgs.vim ];
              };
          };

        expr = lib.filter (lib.hasInfix "vim") (map lib.getName tuxHm.home.packages);
        expected = [ "vim" ];
      }
    );
  };

}
