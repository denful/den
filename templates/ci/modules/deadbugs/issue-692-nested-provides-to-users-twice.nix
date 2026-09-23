# A nested aspect's `provides.to-users` class content must reach the user once.
# Declaring an option there makes a double emission fail loudly
# ("already declared").
{ denTest, ... }:
{
  flake.tests.issue-692-nested-provides-to-users-twice = {

    test-top-level-provides-to-users = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.foo ];
        den.aspects.foo.provides.to-users.homeManager =
          { lib, ... }:
          {
            options.marker = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          };
        expr = igloo.home-manager.users.tux.marker;
        expected = true;
      }
    );

    test-nested-provides-to-users = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.foo ];
        den.aspects.foo.includes = [ den.aspects.foo.bar ];
        den.aspects.foo.bar.provides.to-users.homeManager =
          { lib, ... }:
          {
            options.nested-marker = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          };
        expr = igloo.home-manager.users.tux.nested-marker;
        expected = true;
      }
    );

  };
}
