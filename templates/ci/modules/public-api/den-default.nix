{ denTest, ... }:
{

  flake.tests.den-default.test-includes-owned = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };

      den.default.includes = [ den.aspects.foo ];
      den.aspects.foo.nixos.users.users.tux.description = "pingu";

      expr = igloo.users.users.tux.description;
      expected = "pingu";
    }
  );

  flake.tests.den-default.test-includes-host-function = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };

      den.default.includes = [ den.aspects.foo ];
      den.aspects.foo =
        { host, ... }:
        {
          nixos.users.users.tux.description = "pingu";
        };

      expr = igloo.users.users.tux.description;
      expected = "pingu";
    }
  );

  flake.tests.den-default.test-includes-user-function = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux.userName = "pingu";

      den.default.includes = [ den.aspects.foo ];

      den.aspects.foo =
        { user, ... }:
        {
          nixos.users.users.tux.description = user.userName;
        };

      expr = igloo.users.users.tux.description;
      expected = "pingu";
    }
  );

}
