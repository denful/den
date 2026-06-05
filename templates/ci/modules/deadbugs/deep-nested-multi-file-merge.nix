# Regression: several files each contribute a DIFFERENT child to the same
# deeply-nested namespace node, so that node is itself a colliding sub-key of
# its parent across multiple definitions.
#
# aspectContentType's multi-def branch forwarded sub-keys with a shallow `//`,
# which kept only the last contribution to a colliding sub-key — so all but one
# child vanished from navigation and could not be included. This reproduces the
# kubernetes layout where cilium.nix, hubble-ui.nix and cilium-bgp-resources.nix
# each define a child of services.network.cilium (collision at network → cilium).
#
# Unlike deep-nested-separate-imports (where a/b are distinct DIRECT children of
# sub2, which a shallow `//` handles), here a/b/c live under a shared `grp` node
# that collides across the three definitions one level up.
{ denTest, ... }:
{
  flake.tests.deadbugs.deep-nested-multi-file-merge = {
    test-multi-file-colliding-namespace-merge = denTest (
      { den, igloo, ... }:
      {
        imports = [
          { den.aspects.root.sub1.sub2.grp.a.nixos.environment.variables.FROM_A = "yes"; }
          { den.aspects.root.sub1.sub2.grp.b.nixos.environment.variables.FROM_B = "yes"; }
        ];

        den.aspects.root.sub1.sub2.grp.c.nixos.environment.variables.FROM_C = "yes";

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.root.sub1.sub2.grp.a
          den.aspects.root.sub1.sub2.grp.b
          den.aspects.root.sub1.sub2.grp.c
        ];

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
          hasC = igloo.environment.variables ? FROM_C;
        };
        expected = {
          hasA = true;
          hasB = true;
          hasC = true;
        };
      }
    );
  };
}
