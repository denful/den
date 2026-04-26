# Tests for policy-based transitions (formerly ctx nested into).
# Nested-path into was removed with den.ctx — only flat policies remain.
{ denTest, lib, ... }:
{
  flake.tests.ctx-nested = {

    test-flat-still-works = denTest (
      { den, funnyNames, ... }:
      {
        den.entityIncludes.flat = [ ];

        den.policies.test-root-to-flat = {
          from = "root";
          to = "flat";
          resolve = ctx: if !(builtins.isAttrs ctx) then [ ] else [ ctx ];
          aspects = [
            (
              { x }:
              {
                funny.names = [ x ];
              }
            )
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
        den.entityIncludes.leaf = [
          (
            { v }:
            {
              funny.names = [ v ];
            }
          )
        ];

        imports = [
          {
            den.policies.test-root-to-leaf-a = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "a"; } ];
            };
          }

          {
            den.policies.test-root-to-leaf-b = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "b"; } ];
            };
          }

          {
            den.policies.test-root-to-leaf-c = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "c"; } ];
            };
          }

          {
            den.policies.test-root-to-leaf-d = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "d"; } ];
            };
          }
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
