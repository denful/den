# Regression: a class module taking an optional context arg that is absent
# here (`home ? null` on a host user) alongside one that is present
# (`user ? null`) threw `attribute 'home' missing` once `home` was read: the
# wrapper advertised `home` to the module system, which looked it up in
# `_module.args`. Reported in Matrix.
{ denTest, ... }:
{
  flake.tests.optional-absent-context-arg = {
    # Control: only the absent arg, so the module isn't wrapped.
    test-absent-only = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feature.homeManager =
          {
            home ? null,
            ...
          }:
          {
            programs.atuin.enable = home == null;
          };
        den.aspects."tux@igloo".includes = [ den.aspects.feature ];
        expr = tuxHm.programs.atuin.enable;
        expected = true;
      }
    );
    test-absent-with-present-user = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feature.homeManager =
          {
            home ? null,
            user ? null,
            ...
          }:
          {
            programs.atuin.enable = home == null && user.name == "tux";
          };
        den.aspects."tux@igloo".includes = [ den.aspects.feature ];
        expr = tuxHm.programs.atuin.enable;
        expected = true;
      }
    );
    # A module-system arg alongside keeps the wrapper's other path.
    test-absent-with-user-and-config = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feature.homeManager =
          {
            home ? null,
            user,
            config,
            ...
          }:
          {
            programs.atuin.enable = home == null && user.name == "tux";
            programs.zoxide.enable = config.programs.atuin.enable;
          };
        den.aspects."tux@igloo".includes = [ den.aspects.feature ];
        expr = [
          tuxHm.programs.atuin.enable
          tuxHm.programs.zoxide.enable
        ];
        expected = [
          true
          true
        ];
      }
    );
    test-absent-on-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos =
          {
            user ? null,
            host ? null,
            ...
          }:
          {
            networking.domain = if user == null then host.name else "wrong";
          };
        expr = igloo.networking.domain;
        expected = "igloo";
      }
    );
  };
}
