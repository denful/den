# Two policy.when guards on hasAspect in one aspect: both should fire.
{ denTest, ... }:
{
  flake.tests.deadbugs.policy-when-hasaspect-pair = {

    test-both-guards-fire = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.aspect1 = {
          homeManager.programs.atuin.enable = true;
        };

        den.aspects.aspect2 = {
          homeManager.programs.atuin.daemon.enable = true;
        };

        den.aspects.aspect3 =
          let
            aspect1Policy = den.lib.policy.when ({ user, ... }: user.hasAspect den.aspects.aspect1) {
              homeManager.programs.atuin.settings.foo = "bar";
            };

            aspect2Policy = den.lib.policy.when ({ user, ... }: user.hasAspect den.aspects.aspect2) {
              homeManager.programs.atuin.settings.bar = "baz";
            };
          in
          {
            includes = [
              aspect1Policy
              aspect2Policy
            ];
          };

        den.aspects.tux = {
          includes = [
            den.aspects.aspect1
            den.aspects.aspect2
            den.aspects.aspect3
          ];
        };

        expr = {
          foo = tuxHm.programs.atuin.settings.foo or null;
          bar = tuxHm.programs.atuin.settings.bar or null;
        };
        expected = {
          foo = "bar";
          bar = "baz";
        };
      }
    );

  };
}
