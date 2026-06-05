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
    let
      inherit (den.lib.policy) include;
    in
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.igloo.policies.to-users =
        { host, user, ... }:
        [
          (include {
            includes = [ den.provides.define-user ];
          })
        ];
      den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];
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
