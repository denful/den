# Bare function aspect merged with static config.
# https://github.com/denful/den/pull/408
{ denTest, lib, ... }:
{
  flake.tests.deadbugs-issue-408 = {
    test-function-aspect-with-static-merge = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.foo ];

        imports =
          let
            one = {
              den.aspects.foo =
                { host, ... }:
                {
                  nixos.environment.sessionVariables.FOO = host.name;
                };
            };
            two = {
              den.aspects.foo.nixos =
                { pkgs, ... }:
                {
                  environment.systemPackages = [ pkgs.hello ];
                };
            };
          in
          [
            one
            two
          ];

        expr = {
          hello = lib.elem "hello" (map lib.getName igloo.environment.systemPackages);
          FOO = igloo.environment.sessionVariables.FOO;
        };
        expected.FOO = "igloo";
        expected.hello = true;
      }
    );
  };
}
