# Regression: `(den.batteries.user-shell "<shell>")` in den.default.includes
# defined users.users.<name>.shell twice, so the host did not evaluate. The
# include is registered at the host scope and again at the user scope. Each
# registration built a new policy record, which did not compare equal to the
# first, so it got its own identity and delivered the shell a second time.
# Worked on v0.19.0.
{ denTest, ... }:
{
  flake.tests.user-shell-den-default = {

    # The battery in den.default.includes must still set the shell once.
    test-user-shell-in-den-default = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [
          den.batteries.define-user
          (den.batteries.user-shell "fish")
        ];

        expr = {
          shell = igloo.users.users.tux.shell.pname;
          fish = igloo.programs.fish.enable;
        };
        expected = {
          shell = "fish";
          fish = true;
        };
      }
    );

    # Control: the same battery on the user alone.
    test-user-shell-on-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [ den.batteries.define-user ];
        den.aspects.tux.includes = [ (den.batteries.user-shell "fish") ];

        expr = {
          shell = igloo.users.users.tux.shell.pname;
          fish = igloo.programs.fish.enable;
        };
        expected = {
          shell = "fish";
          fish = true;
        };
      }
    );

  };
}
