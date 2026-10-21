# Issue #629: requesting `user` inside an aspect's `nixos` class module silently
# drops the module when the aspect is included at HOST scope.
#
# Reporter includes an aspect at host scope whose `nixos` class module names
# `user`. At host scope the emit ctx has `host` but no `user`, so wrapClassModule
# marks it `unsatisfied` and wrap-classes drops it (silently — the lib.warn is
# attached to the discarded module and never forced). The aspect-level parametric
# form `{ user, ... }: { nixos = ...; }` works because the bind handler fans the
# aspect over host.users; class-module args never reach that fan-out.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-629-class-module-user-arg = {

    # FAILING: class module names `user`, aspect included at host scope.
    # Host has one user; the module should fan per-user like the aspect form.
    test-class-module-user-arg-at-host-scope = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.desktop.cosmic.nixos =
          { user, ... }:
          {
            environment.etc."cosmic-autologin".text = user.userName;
          };

        den.aspects.igloo.includes = [ den.aspects.desktop.cosmic ];

        expr = igloo.environment.etc."cosmic-autologin".text or "<skipped>";
        expected = "tux";
      }
    );

    # CONTROL: aspect-level parametric form of the same thing — already works.
    test-aspect-level-parametric-at-host-scope = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.desktop.cosmic =
          { user, ... }:
          {
            nixos.environment.etc."cosmic-autologin".text = user.userName;
          };

        den.aspects.igloo.includes = [ den.aspects.desktop.cosmic ];

        expr = igloo.environment.etc."cosmic-autologin".text or "<skipped>";
        expected = "tux";
      }
    );

  };
}
