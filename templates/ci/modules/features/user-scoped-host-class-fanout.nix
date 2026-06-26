# Regression: a STATIC (constant-name) aspect included via den.schema.user.includes
# whose host-class (nixos) content NAMES `user` must fan PER-USER. Its content
# merges into the single shared host config, so without per-content keying it
# collapses N users → 1 (dedupByKey on a sid-free aspect identity) and all but
# one user's content is dropped before evaluation. The fix keys class content by
# the entity kinds its function NAMES (emit-classes.nix): naming `user` ⇒ per-user
# identity. Content that names NO entity kind stays singular (shared infra aspects
# like impermanence keep deduping) — exercised throughout the rest of the suite.
{ denTest, ... }:
{
  flake.tests.user-scoped-host-class-fanout = {

    # Two users on one host. A static user-include sets per-user SYSTEM config
    # (environment.etc keyed by user.name). BOTH must materialize on the host.
    test-static-user-include-nixos-fans-per-user = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        # Static aspect: same identity for every user. Its nixos content names
        # `user`, so it must key per-user rather than collapse to one identity.
        den.aspects.per-user-probe.nixos =
          { user, ... }:
          {
            environment.etc."probe-${user.name}".text = "user=${user.name}";
          };
        den.schema.user.includes = [ den.aspects.per-user-probe ];

        expr = lib.sort (a: b: a < b) (
          builtins.filter (n: lib.hasPrefix "probe-" n) (builtins.attrNames igloo.environment.etc)
        );
        # Pre-fix this was a single entry (one arbitrary user won the dedup).
        expected = [
          "probe-pingu"
          "probe-tux"
        ];
      }
    );

    # The per-user content closes over the RIGHT user (no cross-user leakage):
    # each probe's text reflects its own user, not the survivor's.
    test-per-user-content-binds-own-user = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.per-user-probe.nixos =
          { user, ... }:
          {
            environment.etc."probe-${user.name}".text = "user=${user.name}";
          };
        den.schema.user.includes = [ den.aspects.per-user-probe ];

        expr = {
          tux = igloo.environment.etc."probe-tux".text;
          pingu = igloo.environment.etc."probe-pingu".text;
        };
        expected = {
          tux = "user=tux";
          pingu = "user=pingu";
        };
      }
    );

  };
}
