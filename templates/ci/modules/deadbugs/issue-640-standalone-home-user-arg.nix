# Issue #640: a class module requesting the `user` entity arg is silently
# dropped on a standalone home whose user cannot be resolved from a DECLARED
# host — no error, no warning, the whole class block disappears.
#
# `nix/lib/entities/home.nix` only bound `user` when the home is named
# `user@host` and that host is declared in `den.hosts` with that user. Without
# it, `wrapFunctionModule` takes the `missingDenArgNames` path and returns
# `unsatisfied = true`; the module is dropped, and the `lib.warn` it attaches is
# never forced, so even the existing warning stays invisible.
{ denTest, ... }:
let
  outOf =
    config: home: config.flake.homeConfigurations.${home}.config.home.file."OUT".text or "<dropped>";
in
{
  flake.tests.deadbugs.issue-640-standalone-home-user-arg = {

    # A bare standalone home: no host in the name at all.
    test-bare-standalone-home-binds-user = denTest (
      { den, config, ... }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den._.define-user ];

        den.homes.x86_64-linux.tux = { };

        den.aspects.probe.homeManager =
          { user, ... }:
          {
            home.file."OUT".text = "user=${user.name}";
          };
        den.aspects.tux.includes = [ den.aspects.probe ];

        expr = outOf config "tux";
        expected = "user=tux";
      }
    );

    # `user@host` where the host is NOT declared in den.hosts — home.nix
    # synthesizes the host, so the user must come from the home too.
    test-synthetic-host-home-binds-user = denTest (
      { den, config, ... }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den._.define-user ];

        den.homes.x86_64-linux."tux@astra" = { };

        den.aspects.probe.homeManager =
          { user, ... }:
          {
            home.file."OUT".text = "user=${user.name}";
          };
        den.aspects.tux.includes = [ den.aspects.probe ];

        expr = outOf config "tux@astra";
        expected = "user=tux";
      }
    );

    # CONTROL: `user@host` with the host declared — the path that already
    # resolved `user` from `den.hosts`, and must keep resolving it from there.
    test-declared-host-home-still-binds-user = denTest (
      { den, config, ... }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den._.define-user ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux."tux@igloo" = { };

        den.aspects.probe.homeManager =
          { user, ... }:
          {
            home.file."OUT".text = "user=${user.name}";
          };
        den.aspects.tux.includes = [ den.aspects.probe ];

        expr = outOf config "tux@igloo";
        expected = "user=tux";
      }
    );

    # CONTROL: `{ home, ... }` on a bare standalone home already worked and must
    # keep working — it is what shows the drop is specific to `user`.
    test-bare-standalone-home-binds-home = denTest (
      { den, config, ... }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den._.define-user ];

        den.homes.x86_64-linux.tux = { };

        den.aspects.probe.homeManager =
          { home, ... }:
          {
            home.file."OUT".text = "home=${home.userName}";
          };
        den.aspects.tux.includes = [ den.aspects.probe ];

        expr = outOf config "tux";
        expected = "home=tux";
      }
    );

  };
}
