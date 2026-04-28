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
          from = "root";
          to = "flat";
          __functor =
            _: ctx:
            let
              inherit (den.lib.policy) resolve include;
            in
            if !(builtins.isAttrs ctx) then
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
        den.default.policies = [ "test-root-to-flat" ];

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
                from = "root";
                to = "leaf";
                __functor =
                  _: _:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  [ (resolve { v = "a"; }) ];
              };
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-b = {
                from = "root";
                to = "leaf";
                __functor =
                  _: _:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  [ (resolve { v = "b"; }) ];
              };
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-c = {
                from = "root";
                to = "leaf";
                __functor =
                  _: _:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  [ (resolve { v = "c"; }) ];
              };
            }
          )

          (
            { den, ... }:
            {
              den.policies.test-root-to-leaf-d = {
                from = "root";
                to = "leaf";
                __functor =
                  _: _:
                  let
                    inherit (den.lib.policy) resolve;
                  in
                  [ (resolve { v = "d"; }) ];
              };
            }
          )
        ];
        den.default.policies = [
          "test-root-to-leaf-a"
          "test-root-to-leaf-b"
          "test-root-to-leaf-c"
          "test-root-to-leaf-d"
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
