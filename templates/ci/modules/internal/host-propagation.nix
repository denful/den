{ denTest, ... }:
{

  # This test uses the `funny.names` test option to
  # demostrate different places and context-aspects that
  # can contribute configurations to the host.
  flake.tests.ctx-transformation.test-host = denTest (
    {
      den,
      lib,
      show,
      funnyNames,
      ...
    }:
    let
      inherit (den.lib) parametric take;
      inherit (den.lib.policy) include;

      keys = ctx: "{${builtins.concatStringsSep "," (builtins.attrNames ctx)}}";
    in
    {

      den.hosts.x86_64-linux.igloo.users.tux = { };

      den.aspects.igloo.funny.names = [ "host-owned" ];
      den.aspects.igloo.includes = [
        den.aspects.igloo.policies.to-users
        (take.exactly (
          { host }:
          {
            funny.names = [ "host-exact" ];
          }
        ))
        (take.exactly (
          { host, user }:
          {
            funny.names = throw "unreachable";
          }
        ))
      ];
      den.aspects.igloo.policies.to-users =
        { host, user, ... }:
        [
          (include {
            includes = [
              { funny.names = [ "host-static" ]; }

              (
                { host, ... }@ctx:
                {
                  funny.names = [ "host-lax ${keys ctx}" ];
                }
              )
              (take.atLeast (
                { host, never }:
                {
                  funny.names = throw "unreachable";
                }
              ))

              (
                { host, user, ... }@ctx:
                {
                  funny.names = [ "host+user-lax ${keys ctx}" ];
                }
              )
              (take.exactly (
                { host, user }:
                {
                  funny.names = [ "host+user-exact" ];
                }
              ))
              (take.atLeast (
                {
                  host,
                  user,
                  never,
                }:
                {
                  funny.names = throw "unreachable";
                }
              ))
            ];
          })
        ];

      den.aspects.tux.funny.names = [ "user-owned" ];
      den.aspects.tux.includes = [
        { funny.names = [ "user-static" ]; }

        (
          { user, ... }@ctx:
          {
            funny.names = [ "user-lax ${keys ctx}" ];
          }
        )
        (take.exactly (
          { host, user }:
          {
            funny.names = [ "user-exact" ];
          }
        ))
        (take.atLeast (
          {
            host,
            user,
            never,
          }:
          {
            funny.names = throw "unreachable";
          }
        ))
      ];

      den.schema.host.includes = [
        { funny.names = [ "hm-host detected" ]; }
        (
          { host, ... }@ctx:
          {
            funny.names = [ "hm-host host-lax ${keys ctx}" ];
          }
        )
      ];

      den.schema.user.includes = [
        (
          { host, user, ... }@ctx:
          {
            funny.names = [ "hm-user lax ${keys ctx}" ];
          }
        )
      ];

      den.default.funny.names = [ "default-owned" ];
      den.default.includes = [
        {
          name = "default-static-inc";
          funny.names = [ "default-static" ];
        }
        (ctx: {
          name = "default-anyctx-inc";
          funny.names = [ "default-anyctx ${keys ctx}" ];
        })

        (
          { host, ... }@ctx:
          {
            name = "default-host-lax-inc";
            funny.names = [ "default-host-lax ${keys ctx}" ];
          }
        )
        (
          { user, ... }@ctx:
          {
            name = "default-user-lax-inc";
            funny.names = [ "default-user-lax ${keys ctx}" ];
          }
        )
        (
          { host, user, ... }@ctx:
          {
            name = "default-host+user-lax-inc";
            funny.names = [ "default-host+user-lax ${keys ctx}" ];
          }
        )
      ];

      expr = funnyNames (
        den.lib.resolveEntity "host" {
          host = den.hosts.x86_64-linux.igloo;
        }
      );

      # Post-ctx semantics: default resolves once via host→default.
      # Includes fire once with available context. Deferred includes
      # (requiring user) fire when context widens via drain-deferred.
      # No include fires twice — no per-source re-resolution.
      expected = [
        "default-anyctx {host}"
        "default-host+user-lax {host,user}"
        "default-host-lax {host}"

        "default-owned"

        "default-static"

        "default-user-lax {user}"

        "hm-host detected"
        "hm-host host-lax {host}"
        "hm-user lax {host,user}"

        "host+user-exact"
        "host+user-lax {host,user}"

        "host-exact"
        "host-lax {host}"

        "host-owned"
        "host-static"

        "user-exact"
        "user-lax {user}"
        "user-owned"
        "user-static"
      ];

    }
  );

}
