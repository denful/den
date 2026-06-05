{ denTest, ... }:
{
  flake.tests.deadbugs.deep-nested-separate-imports = {
    test-deep-nested-separate-imports = denTest (
      { den, igloo, ... }:
      {
        imports = [
          { den.aspects.root.sub1.sub2.a.nixos.environment.variables.FROM_A = "yes"; }
        ];

        den.aspects.root.sub1.sub2.b.nixos.environment.variables.FROM_B = "yes";

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.root.sub1.sub2.a
          den.aspects.root.sub1.sub2.b
        ];

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = true;
          hasB = true;
        };
      }
    );
  };
}
