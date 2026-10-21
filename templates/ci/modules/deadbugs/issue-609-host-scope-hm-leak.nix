# Acceptance for denful/den#609: a host-scope aspect must NOT leak homeManager
# content into its users' HM evaluation. The formal rule (class-local emission):
# a parametric aspect at scope S (entity kind K_S) destructuring entity-kind K_a
#   - K_a in ctx          → bind once at S
#   - K_a descendant of S → fan out over S's K_a-children, EMIT AT S
#   - neither             → misplaced → whole aspect inert, silently
# Emission is always class-local to the EMITTING scope. The host scope resolves
# nixos but NOT homeManager, so homeManager content in a host-scope aspect is
# inert — it never reaches users. This is the #609 fix: homeManager must reach
# users only via a to-users policy, never a bare host-scope include.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-609 = {

    # (a) { user, … } at host scope: user is a descendant of host → fan out.
    # The nixos content lands per-user, merged on the host, once per user.
    test-user-param-nixos-lands-on-host = denTest (
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

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "nixos ${user.name}" ];
              homeManager.home.sessionVariables.LEAK = "hm ${user.name}";
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "nixos pingu"
          "nixos tux"
        ];
      }
    );

    # (b) Same aspect's homeManager content does NOT reach users' HM eval.
    # The host scope resolves no homeManager class → the LEAK is inert.
    test-user-param-hm-does-not-leak = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              homeManager.home.sessionVariables.LEAK = "hm ${user.name}";
            }
          )
        ];

        expr = [
          (tuxHm.home.sessionVariables.LEAK or "MISSING")
          (pinguHm.home.sessionVariables.LEAK or "MISSING")
        ];
        expected = [
          "MISSING"
          "MISSING"
        ];
      }
    );

    # (c) Plain (non-parametric) host-scope aspect with homeManager content:
    # still class-local to the host → MISSING in users' HM eval.
    test-plain-hm-at-host-missing = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          {
            homeManager.home.sessionVariables.LEAK = "plain";
          }
        ];

        expr = tuxHm.home.sessionVariables.LEAK or "MISSING";
        expected = "MISSING";
      }
    );

    # (d) { host, … } host-scope aspect with homeManager content: host is in ctx
    # (bound once), but the emission is still class-local to the host → MISSING.
    test-host-param-hm-at-host-missing = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          (
            { host, ... }:
            {
              homeManager.home.sessionVariables.LEAK = "hm ${host.name}";
            }
          )
        ];

        expr = tuxHm.home.sessionVariables.LEAK or "MISSING";
        expected = "MISSING";
      }
    );

  };
}
