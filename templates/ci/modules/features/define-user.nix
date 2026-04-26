{ denTest, ... }:
{

  flake.tests.define-user.test-on-nixos-included-at-user = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.tux.includes = [ den.provides.define-user ];
      expr = igloo.users.users.tux.isNormalUser;
      expected = true;
    }
  );

  flake.tests.define-user.test-on-nixos-included-at-host = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.schema.user.includes = [ den.provides.mutual-provider ];
      den.aspects.igloo.provides.to-users.includes = [ den.provides.define-user ];
      expr = igloo.users.users.tux.isNormalUser;
      expected = true;
    }
  );

  flake.tests.define-user.test-on-nixos-included-at-default = denTest (
    {
      den,
      lib,
      igloo,
      ...
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.default.includes = [ den.provides.define-user ];
      expr = igloo.users.users.tux.isNormalUser;
      expected = true;
    }
  );

}
