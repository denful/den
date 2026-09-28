# A `to-hosts` provide on an aspect reached through a host's user projection
# (igloo.provides.tux) registers its policy at the user scope after that
# scope's late dispatch ran; it must still fire.
{ denTest, ... }:
{
  flake.tests.quirk-host-provides-user-to-hosts =
    let
      common =
        { den, ... }:
        {
          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.quirks.test.description = "";
          den.aspects.test-producer.test = "Test";
          den.aspects.test-consumer.provides.to-hosts.nixos =
            { user, test, ... }:
            {
              users.users.${user.name}.description = builtins.head test;
            };
        };
    in
    {
      test-direct-user-include = denTest (
        { den, igloo, ... }:
        {
          imports = [ common ];
          den.aspects.tux.includes = [
            den.aspects.test-producer
            den.aspects.test-consumer
          ];
          expr = igloo.users.users.tux.description;
          expected = "Test";
        }
      );

      test-host-provides-user-include-no-quirk = denTest (
        { den, igloo, ... }:
        {
          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.aspects.test-consumer.provides.to-hosts.nixos =
            { user, ... }:
            {
              users.users.${user.name}.description = "X";
            };
          den.aspects.igloo.provides.tux.includes = [ den.aspects.test-consumer ];
          expr = igloo.users.users.tux.description;
          expected = "X";
        }
      );

      test-host-provides-user-include = denTest (
        { den, igloo, ... }:
        {
          imports = [ common ];
          den.aspects.tux.includes = [ den.aspects.test-producer ];
          den.aspects.igloo.provides.tux.includes = [ den.aspects.test-consumer ];
          expr = igloo.users.users.tux.description;
          expected = "Test";
        }
      );
    };
}
