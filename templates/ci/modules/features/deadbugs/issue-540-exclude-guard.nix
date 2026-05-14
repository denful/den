{ denTest, lib, ... }:
{
  flake.tests.issue-540-exclude-guard = {
    # Known limitation: guards that pass eagerly don't see later excludes.
    # starship is excluded for tux, but the guard fires before the exclude.
    # Fixing this requires scope-aware drain timing — tracked separately.
    test-exclude-does-not-suppress-eager-guard = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.starship.homeManager.programs.starship.enable = true;
        den.aspects.jujutsu = {
          homeManager.programs.jujutsu.enable = true;
          includes = [
            (policy.when ({ user, ... }: user.hasAspect den.aspects.starship) (
              policy.include {
                homeManager.programs.starship.settings.custom.jj = {
                  command = "prompt";
                  when = true;
                };
              }
            ))
          ];
        };

        den.aspects.features.includes = [
          den.aspects.starship
          den.aspects.jujutsu
        ];

        den.aspects.igloo = {
          includes = [ den.aspects.igloo.policies.to-users ];
          policies.to-users =
            { user, ... }:
            [
              (policy.include den.aspects.features)
            ]
            ++ lib.optional (user.userName == "tux") (policy.exclude den.aspects.starship);
        };

        expr = {
          tux-starship = igloo.home-manager.users.tux.programs.starship.enable;
          pingu-starship = igloo.home-manager.users.pingu.programs.starship.enable;
          tux-jj = igloo.home-manager.users.tux.programs.starship.settings ? custom;
          pingu-jj = igloo.home-manager.users.pingu.programs.starship.settings ? custom;
        };
        expected = {
          tux-starship = false;
          pingu-starship = true;
          tux-jj = true; # ideally false, but eager guard doesn't see later exclude
          pingu-jj = true;
        };
      }
    );
  };
}
