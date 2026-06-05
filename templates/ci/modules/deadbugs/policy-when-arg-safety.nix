# Regression: policy.when wraps the predicate in fn = ctx: if predicate ctx ...
# which loses the predicate's argument signature.  resolveArgsSatisfied sees
# the wrapper as accepting any context, so the policy fires in scopes where
# the predicate's required args are missing → crash.
#
# The bug requires cross-scope dispatch: a host-scoped policy.when with
# { host, ... } predicate is picked up during standalone home resolution
# via late dispatch, firing in a context that lacks host.
{ denTest, ... }:
{
  flake.tests.policy-when-arg-safety = {

    # policy.when with { host, ... } predicate must not crash when a
    # standalone home triggers cross-scope dispatch
    test-when-strict-predicate-safe-with-standalone-home = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        den.schema.host.includes = [
          {
            includes = [
              (den.lib.policy.when ({ host, ... }: host.name == "igloo") (
                den.lib.policy.mkPolicy "guarded-host-policy" (_: [
                  (den.lib.policy.include { nixos.services.openssh.enable = true; })
                ])
              ))
            ];
          }
        ];

        expr = {
          host-gets-policy = igloo.services.openssh.enable;
          home-resolves = config.flake.homeConfigurations ? tux;
        };
        expected = {
          host-gets-policy = true;
          home-resolves = true;
        };
      }
    );

    # Optional args in the predicate should not trigger the safety check —
    # the policy should still fire when the optional arg is absent.
    test-when-optional-args-still-fire = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";

        den.schema.host.includes = [
          {
            includes = [
              (den.lib.policy.when
                (
                  {
                    host ? null,
                    ...
                  }:
                  host != null
                )
                (
                  den.lib.policy.mkPolicy "optional-arg-policy" (_: [
                    (den.lib.policy.include { nixos.services.openssh.enable = true; })
                  ])
                )
              )
            ];
          }
        ];

        expr = {
          host-gets-policy = igloo.services.openssh.enable;
          home-resolves = config.flake.homeConfigurations ? tux;
        };
        expected = {
          host-gets-policy = true;
          home-resolves = true;
        };
      }
    );

  };
}
