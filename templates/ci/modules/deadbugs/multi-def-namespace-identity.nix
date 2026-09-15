# Regression: navigating through a MULTI-DEF nested namespace key strips
# aspect identity from its children.
#
# aspectContentType's multi-def branch returns `subForwarded // { __aspectChain;
# __contentValues; }` — the colliding key itself is tagged, but its forwarded
# children are raw attrsets with no `name` and no `__aspectChain`. wrapChild then
# falls through nameless and children.nix renames the child to
# `<parent>/<anon>:<idx>`, so the same aspect included via two paths gets two
# identities: emit-class dedup fails and the class content double-applies
# (equal-priority option conflicts for scalar options, duplicated entries for
# list options) when the content re-emits in a spawned user resolution.
#
# Real-world shape: gpg.nix and ssh.nix both define children of
# den.aspects.apps.dev.security (multi-def at `dev`), and
# apps.dev.security.gpg is included by both roles.dev and roles.dev-gui —
# pinentry.package then gets two equal-priority definitions in the user's
# home-manager config.
#
# The single-def path is unaffected (annotatedMerged tags those children),
# which is why 3-level aspects like apps.shell.foo dedup fine.
{ denTest, ... }:
{
  flake.tests.multi-def-namespace-identity = {

    # Aspect under a multi-def key, included via two roles → its homeManager
    # content must reach the user's HM config exactly once.
    test-multi-def-child-dedups-across-two-includes = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        imports = [
          # Two "files" each contribute a child of apps.dev.security →
          # multi-def collision at `dev` (and `security`).
          {
            # `host` makes the block context-dependent (resolved per node),
            # matching real aspects — a plain attrset would dedup by value
            # equality and mask the identity bug.
            den.aspects.apps.dev.security.gpg.homeManager =
              { host, ... }:
              {
                home.sessionPath = [ "/dummy-gpg" ];
              };
          }
          { den.aspects.apps.dev.security.ssh.homeManager.programs.vim.enable = true; }
        ];

        den.aspects.roles.r1.includes = [ den.aspects.apps.dev.security.gpg ];
        den.aspects.roles.r2.includes = [ den.aspects.apps.dev.security.gpg ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          den.aspects.roles.r1
          den.aspects.roles.r2
        ];
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = builtins.length (lib.filter (p: p == "/dummy-gpg") tuxHm.home.sessionPath);
        expected = 1;
      }
    );

    # Same, two levels deeper — the annotation must recurse, not just tag the
    # first forwarded level.
    test-deep-multi-def-child-dedups = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        imports = [
          {
            den.aspects.svc.net.mesh.core.agent.homeManager =
              { host, ... }:
              {
                home.sessionPath = [ "/dummy-agent" ];
              };
          }
          { den.aspects.svc.net.mesh.edge.proxy.homeManager.programs.vim.enable = true; }
        ];

        den.aspects.roles.r1.includes = [ den.aspects.svc.net.mesh.core.agent ];
        den.aspects.roles.r2.includes = [ den.aspects.svc.net.mesh.core.agent ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          den.aspects.roles.r1
          den.aspects.roles.r2
        ];
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = builtins.length (lib.filter (p: p == "/dummy-agent") tuxHm.home.sessionPath);
        expected = 1;
      }
    );

  };
}
