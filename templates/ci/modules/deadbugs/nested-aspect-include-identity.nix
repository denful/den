# Regression: a deeply-nested aspect (deep.grp.svc) included via TWO scopes —
# host-scope through a role, and user-scope through a per-user entity-named
# aspect auto-included by a policy — must resolve to its OWN identity in both,
# so its nixos content dedups across scopes instead of applying twice.
#
# Reproduces apps.gaming.steam included via BOTH roles.gaming (host) and a
# per-user entity-named aspect's includes (user-aspect-auto-include policy):
# the navigated nested aspect carried __provider but no name, so wrapChild left
# it nameless and children.nix renamed it to <parent>/<anon>:<idx>. That gave a
# different identity on the user path than the host path, defeating cross-scope
# dedup, so steam's programs.steam.package was defined twice.
{ denTest, ... }:
{
  flake.tests.deadbugs.nested-aspect-include-identity = {
    test-nested-include-dedups-across-scopes = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        # Mirror the consumer's policy: auto-include den.aspects.<host>.<user>
        # at user scope if it exists.
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "user-aspect-auto-include" (
            { host, user, ... }:
            lib.optional (den.aspects ? ${host.name} && den.aspects.${host.name} ? ${user.name}) (
              den.lib.policy.include den.aspects.${host.name}.${user.name}
            )
          ))
        ];

        den.aspects.deep.grp.svc.nixos.boot.kernelParams = [ "den-dedup-marker" ];

        # Host-scope inclusion (via a role the host includes).
        den.aspects.gaming.includes = [ den.aspects.deep.grp.svc ];

        # User-scope inclusion (entity-named aspect, auto-included by the policy).
        den.aspects.igloo.tux.includes = [ den.aspects.deep.grp.svc ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.gaming ];

        # Deduped across scopes → marker once; with distinct anon identities on
        # the user path the nixos content applies twice → marker twice.
        expr = builtins.length (builtins.filter (p: p == "den-dedup-marker") igloo.boot.kernelParams);
        expected = 1;
      }
    );
  };
}
