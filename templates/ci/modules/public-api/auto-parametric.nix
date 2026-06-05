{ denTest, ... }:
{
  flake.tests.auto-parametric = {

    # Helper aspect NOT linked to any host but included transitively.
    # Without auto-parametric, its __functor.__functionArgs = { aspect = false }
    # so canTake.atLeast { host } helper → false → silently dropped.
    test-helper-aspect-dispatches-with-host-ctx = denTest (
      { den, igloo, ... }:
      {
        den.aspects.my-helper.includes = [
          (
            { host, ... }:
            {
              nixos.networking.hostName = host.name;
            }
          )
        ];
        den.aspects.igloo.includes = [ den.aspects.my-helper ];
        den.hosts.x86_64-linux.igloo = { };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Chained helper: igloo → a → b, all with { host } includes.
    test-helper-chain-propagates-host-ctx = denTest (
      { den, igloo, ... }:
      {
        den.aspects.b.includes = [
          (
            { host, ... }:
            {
              nixos.networking.hostName = "${host.name}-ok";
            }
          )
        ];
        den.aspects.a.includes = [ den.aspects.b ];
        den.aspects.igloo.includes = [ den.aspects.a ];
        den.hosts.x86_64-linux.igloo = { };

        expr = igloo.networking.hostName;
        expected = "igloo-ok";
      }
    );

    # Anonymous attrset aspect in includes also works without explicit parametric.
    test-anon-fn-include-in-helper = denTest (
      { den, igloo, ... }:
      {
        den.aspects.my-helper.includes = [
          (
            { host, ... }:
            {
              nixos.users.users.tux.description = host.name;
            }
          )
        ];
        den.aspects.igloo.includes = [ den.aspects.my-helper ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = igloo.users.users.tux.description;
        expected = "igloo";
      }
    );

    # Helper with own class-specific config (owned) also flows correctly.
    test-helper-owned-config-preserved = denTest (
      { den, igloo, ... }:
      {
        den.aspects.helper-with-owned = {
          nixos.networking.hostName = "from-helper-owned";
          includes = [ ];
        };
        den.aspects.igloo.includes = [ den.aspects.helper-with-owned ];
        den.hosts.x86_64-linux.igloo = { };

        expr = igloo.networking.hostName;
        expected = "from-helper-owned";
      }
    );

    test-second-level-helper-owned-config-preserved = denTest (
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

        den.aspects.second-with-owned = {
          nixos.networking.hostName = "from-second-owned";
          includes = [
            (
              { host, user }:
              {
                nixos.users.users.${user.name}.description = host.name;
              }
            )
          ];
        };
        den.aspects.helper.includes = [ den.aspects.second-with-owned ];
        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [ den.aspects.helper ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = [
          igloo.networking.hostName
          igloo.users.users.tux.description
        ];
        expected = [
          "from-second-owned"
          "igloo"
        ];
      }
    );

    test-second-provides-helper-owned-config-preserved = denTest (
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

        den.aspects.second.provides.with-owned = {
          nixos.networking.hostName = "from-second-owned";
          includes = [
            (
              { host, user }:
              {
                nixos.users.users.${user.name}.description = host.name;
              }
            )
          ];
        };
        den.aspects.helper.includes = [ den.aspects.second.provides.with-owned ];
        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [ den.aspects.helper ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = [
          igloo.networking.hostName
          igloo.users.users.tux.description
        ];
        expected = [
          "from-second-owned"
          "igloo"
        ];
      }
    );

  };
}
