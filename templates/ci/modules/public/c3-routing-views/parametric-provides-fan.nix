# A parametric aspect fanned per user registers one cross-provide policy PER FAN
# INSTANCE, and that is load-bearing: each instance's `provides` already carries
# its own entity binding, so collapsing them to the ctxId-free base identity
# delivers the last instance's binding to every user. Keyed on the base identity
# this test reads [ "/opt/vic" ] for tux.
{ denTest, ... }:
{
  flake.tests.deadbugs.parametric-provides-fan = {

    test-parametric-provides-keeps-per-instance-binding = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          vic = { };
        };

        den.aspects.igloo.includes = [ den.aspects.tools ];

        den.aspects.tools =
          { user, ... }:
          {
            provides.to-users.homeManager.home.sessionPath = [ "/opt/${user.userName}" ];
          };

        # Value, not count: a length-only assertion reads 1 under both keyings
        # and cannot see that the wrong user's binding arrived.
        expr = tuxHm.home.sessionPath or [ ];
        expected = [ "/opt/tux" ];
      }
    );

  };
}
