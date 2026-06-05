{ denTest, ... }:
{
  flake.tests.issue-nested-key-exclude = {
    # Excluding a nested key (sub-aspect defined without _ prefix) should
    # work the same as excluding a provides sub-aspect.
    test-nested-key-exclude = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.my-aspect = {
          includes = with den.aspects.my-aspect; [
            sub-aspect1
            sub-aspect2
          ];
          sub-aspect1.nixos.environment.variables.SUB_ASPECT_1 = "yes";
          _.sub-aspect2.nixos.environment.variables.SUB_ASPECT_2 = "yes";
        };

        den.aspects.igloo.includes = [
          den.aspects.my-aspect
        ];
        den.aspects.igloo.excludes = [
          den.aspects.my-aspect.sub-aspect1
          den.aspects.my-aspect.sub-aspect2
        ];

        expr = {
          sub-aspect1 = igloo.environment.variables ? SUB_ASPECT_1;
          sub-aspect2 = igloo.environment.variables ? SUB_ASPECT_2;
        };
        expected = {
          sub-aspect1 = false;
          sub-aspect2 = false;
        };
      }
    );
  };
}
