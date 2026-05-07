# Static sub-aspect (attrset with owned class config) included from a
# parametric parent aspect. Regression from the applyDeep fix in #419:
# re-applying takeFn to the sub invoked its default functor in a non-static
# context, which dropped owned class configs.
# https://github.com/denful/den/pull/423
{ denTest, ... }:
{
  flake.tests.deadbugs-issue-423 = {
    test-static-sub-aspect-from-parametric-parent = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # Split across modules so the parametric parent and the static sub
        # don't clash on the same `den.aspects.role` attribute definition.
        imports = [
          {
            den.aspects.role =
              { host, ... }:
              {
                includes = [ den.aspects.role.provides.sub ];
              };
          }
          {
            den.aspects.role.provides.sub.nixos.networking.networkmanager.enable = true;
          }
          {
            den.aspects.igloo.includes = [ den.aspects.role ];
          }
        ];

        expr = igloo.networking.networkmanager.enable;
        expected = true;
      }
    );

  };
}
