# Tests for policy-based transitions (formerly ctx nested into).
# Nested-path into was removed with den.ctx — only flat policies remain.
{ denTest, lib, ... }:
{
  flake.tests.ctx-nested = {

    test-flat-still-works = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.flat.includes = [ ];

        den.policies.test-root-to-flat = {
          to = "flat";
          __functor =
            _:
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
                (resolve ctx)
                (include (
                  { x }:
                  {
                    funny.names = [ x ];
                  }
                ))
              ];
        };
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
              den.policies.test-root-to-leaf-a = {
                to = "leaf";
                __functor =
                  _:
                  {
                    __entityKind ? null,
                    ...
                  }:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  if __entityKind != "root" then [ ] else [ (resolve { v = "a"; }) ];
              };
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-b = {
                to = "leaf";
                __functor =
                  _:
                  {
                    __entityKind ? null,
                    ...
                  }:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  if __entityKind != "root" then [ ] else [ (resolve { v = "b"; }) ];
              };
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-c = {
                to = "leaf";
                __functor =
                  _:
                  {
                    __entityKind ? null,
                    ...
                  }:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  if __entityKind != "root" then [ ] else [ (resolve { v = "c"; }) ];
              };
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-d = {
                to = "leaf";
                __functor =
                  _:
                  {
                    __entityKind ? null,
                    ...
                  }:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  if __entityKind != "root" then [ ] else [ (resolve { v = "d"; }) ];
              };
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
