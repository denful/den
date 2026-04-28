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
          {
            __entityKind ? null,
            ...
          }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          if __entityKind != "root" then
            [ ]
          else
            [
              (resolve.to "flat" ctx)
              (include (
                { x }:
                {
                  funny.names = [ x ];
                }
              ))
            ];
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

        imports = [
          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-a =
                {
                  __entityKind ? null,
                  ...
                }:
                let
                  inherit (den.lib.policy) resolve;
                in
                if __entityKind != "root" then [ ] else [ (resolve.to "leaf" { v = "a"; }) ];
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-b =
                {
                  __entityKind ? null,
                  ...
                }:
                let
                  inherit (den.lib.policy) resolve;
                in
                if __entityKind != "root" then [ ] else [ (resolve.to "leaf" { v = "b"; }) ];
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-c =
                {
                  __entityKind ? null,
                  ...
                }:
                let
                  inherit (den.lib.policy) resolve;
                in
                if __entityKind != "root" then [ ] else [ (resolve.to "leaf" { v = "c"; }) ];
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-d =
                {
                  __entityKind ? null,
                  ...
                }:
                let
                  inherit (den.lib.policy) resolve;
                in
                if __entityKind != "root" then [ ] else [ (resolve.to "leaf" { v = "d"; }) ];
            }
          )
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
