{ denTest, ... }:
{
  flake.tests.deadbugs-issue-311 = {

    test-nested-includes-are-parametric = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [
          (
            { host, ... }:
            {
              homeManager.home.keyboard.model = lib.mkDefault "${host.name}-nested";
              includes = [
                (
                  { user, ... }:
                  {
                    homeManager.home.keyboard.model = lib.mkForce "${user.name}-nested";
                  }
                )
              ];
            }
          )
        ];

        expr = tuxHm.home.keyboard.model;
        expected = "tux-nested";
      }
    );

  };

}
