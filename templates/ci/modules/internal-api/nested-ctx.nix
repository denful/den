# Tests for policy-based transitions (formerly ctx nested into).
# Nested-path into was removed with den.ctx — only flat policies remain.
{ denTest, lib, ... }:
{
  flake.tests.ctx-nested = {

    test-flat-still-works = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.flat.includes = [ ];

        den.policies.test-root-to-flat =
          { ... }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "flat" ctx)
            (include (
              { x }:
              {
                funny.names = [ x ];
              }
            ))
          ];
        den.schema.root.includes = [ den.policies.test-root-to-flat ];
        expr = funnyNames (den.lib.resolveEntity "root" { x = "hi"; });
        expected = [ "hi" ];
      }
    );

    test-into-root-and-child-merge = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.leaf.includes = [
          (
            { v }:
            {
              funny.names = [ v ];
            }
          )
        ];

        den.policies.test-root-to-leaf-a =
          _:
          let
            inherit (den.lib.policy) resolve;
          in
          [ (resolve.to "leaf" { v = "a"; }) ];

        den.policies.test-root-to-leaf-b =
          _:
          let
            inherit (den.lib.policy) resolve;
          in
          [ (resolve.to "leaf" { v = "b"; }) ];

        den.policies.test-root-to-leaf-c =
          _:
          let
            inherit (den.lib.policy) resolve;
          in
          [ (resolve.to "leaf" { v = "c"; }) ];

        den.policies.test-root-to-leaf-d =
          _:
          let
            inherit (den.lib.policy) resolve;
          in
          [ (resolve.to "leaf" { v = "d"; }) ];

        den.schema.root.includes = [
          den.policies.test-root-to-leaf-a
          den.policies.test-root-to-leaf-b
          den.policies.test-root-to-leaf-c
          den.policies.test-root-to-leaf-d
        ];

        expr = funnyNames (den.lib.resolveEntity "root" { });
        expected = [
          "a"
          "b"
          "c"
          "d"
        ];
      }
    );
  };
}
