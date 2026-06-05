# Simplified variant of issue-413 provider sub-aspect bug.
# https://github.com/denful/den/pull/413
{ denTest, ... }:
{
  flake.tests.deadbugs-issue-413 = {

    # Parametric parent unconditionally includes parametric sub
    test-parametric-parent-parametric-sub = denTest (
      { den, igloo, ... }:
      {
        imports = [
          {
            den.aspects.foo =
              { host, ... }:
              {
                includes = [ den.aspects.foo.provides.sub ];
              };
          }
          {
            den.aspects.foo.provides.sub =
              { host, ... }:
              {
                nixos.networking.networkmanager.enable = true;
              };
          }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.foo ];

        expr = igloo.networking.networkmanager.enable;
        expected = true;
      }
    );
  };
}
