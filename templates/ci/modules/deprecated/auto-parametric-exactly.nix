{ denTest, ... }:
{
  flake.tests.auto-parametric = {

    # Explicit parametric.exactly on a helper must NOT be overridden.
    test-explicit-exactly-not-overridden-by-default = denTest (
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

        den.aspects.strict-helper = den.lib.parametric.exactly {
          includes = [
            (
              { host, user, ... }:
              {
                nixos.users.users.${user.name}.description = "strict-${host.name}";
              }
            )
          ];
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [ den.aspects.strict-helper ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        # strict-helper requires exactly { host, user } — since ctx.host only provides
        # { host }, strict-helper is skipped at host level (by exactly semantics).
        # At user level, { host, user } matches → description is set.
        expr = igloo.users.users.tux.description;
        expected = "strict-igloo";
      }
    );

  };
}
