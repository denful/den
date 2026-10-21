# Regression: a `policy.route` (fromClass=homeLinux, intoClass=homeManager)
# registered via `den.schema.user.includes` never delivers content from
# HOST-attached aspects.
#
# A user's homeManager content resolves via spawnNode
# (resolve-at-emitting-node): the spawned walk re-emits the host aspect's
# class content at the spawned scopes, but it neither fires the user-schema
# route policies nor inherits the parent pipeline's registered routes. The
# homeLinux content is emitted (visible in the spawned per-scope partition)
# yet never routed into the collected class (homeManager) — it silently
# drops. The same aspect's homeManager block delivers fine, masking the gap.
#
# Real-world shape: nix-config's home-platform.nix routes
# homeLinux/homeDarwin → homeManager per host platform; gpg's pinentry
# moved into homeLinux and vanished from every generation.
{ denTest, ... }:
{
  flake.tests.deadbugs.route-platform-class-host-aspect = {

    # Control: the same route delivers user-attached homeLinux content.
    test-user-attached-homelinux-routes = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.classes.homeLinux.description = "Home-manager modules for Linux hosts";

        den.policies.homeLinux-to-hm =
          { host, ... }:
          lib.optional (lib.hasSuffix "-linux" host.system) (
            den.lib.policy.route {
              fromClass = "homeLinux";
              intoClass = "homeManager";
              path = [ ];
            }
          );
        den.schema.user.includes = [ den.policies.homeLinux-to-hm ];

        den.aspects.shell-tools = {
          homeManager.programs.vim.enable = true;
          homeLinux.programs.git.enable = true;
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.tux.includes = [ den.aspects.shell-tools ];

        expr = {
          vim = tuxHm.programs.vim.enable;
          git = tuxHm.programs.git.enable;
        };
        expected = {
          vim = true;
          git = true;
        };
      }
    );

    # Host-attached aspect: the homeManager block reaches the user's HM
    # config (via spawnNode), so the homeLinux block routed into homeManager
    # must reach it too.
    test-host-attached-homelinux-routes = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.classes.homeLinux.description = "Home-manager modules for Linux hosts";

        den.policies.homeLinux-to-hm =
          { host, ... }:
          lib.optional (lib.hasSuffix "-linux" host.system) (
            den.lib.policy.route {
              fromClass = "homeLinux";
              intoClass = "homeManager";
              path = [ ];
            }
          );
        den.schema.user.includes = [ den.policies.homeLinux-to-hm ];

        den.aspects.desk-role = {
          homeManager.programs.vim.enable = true;
          homeLinux.programs.git.enable = true;
        };

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.desk-role ];
        # Project host aspects onto the user's homeManager (the standard
        # opt-in; cortex/sini uses the same battery).
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = {
          vim = tuxHm.programs.vim.enable;
          git = tuxHm.programs.git.enable;
        };
        expected = {
          vim = true;
          git = true;
        };
      }
    );

  };
}
