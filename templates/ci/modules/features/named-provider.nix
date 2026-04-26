{ denTest, ... }:
{
  flake.tests.ctx-named-provider = {

    test-self-named-provider = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ "hello-${who}" ];
            }
          )
        ];

        expr = funnyNames (den.lib.resolveEntity "greet" { who = "nix"; });
        expected = [ "hello-nix" ];
      }
    );

    test-self-named-plus-owned = denTest (
      { den, funnyNames, ... }:
      {
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ "hello-${who}" ];
            }
          )
          { funny.names = [ "owned" ]; }
        ];

        expr = funnyNames (den.lib.resolveEntity "greet" { who = "nix"; });
        expected = [
          "hello-nix"
          "owned"
        ];
      }
    );

    test-self-provides-other = denTest (
      {
        den,
        lib,
        funnyNames,
        ...
      }:
      {
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ "hello-${who}" ];
            }
          )
        ];

        den.schema.other.includes = [ ];
        den.policies.test-greet-to-other = {
          from = "greet";
          to = "other";
          resolve = ctx: if !(ctx ? who) then [ ] else lib.singleton ctx;
          aspects = [
            (
              { who }:
              {
                funny.names = [ "other-${who}" ];
              }
            )
          ];
        };
        den.default.policies = [ "test-greet-to-other" ];

        expr = funnyNames (den.lib.resolveEntity "greet" { who = "nix"; });
        expected = [
          "hello-nix"
          "other-nix"
        ];
      }
    );

    test-named-provider-with-into = denTest (
      {
        den,
        lib,
        funnyNames,
        ...
      }:
      {
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ who ];
            }
          )
        ];
        den.schema.yell.includes = [ ];
        den.policies.test-greet-to-yell = {
          from = "greet";
          to = "yell";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { shout = lib.toUpper ctx.who; } ];
          aspects = [
            (
              { shout }:
              {
                funny.names = [ shout ];
              }
            )
          ];
        };
        den.default.policies = [ "test-greet-to-yell" ];

        expr = funnyNames (den.lib.resolveEntity "greet" { who = "world"; });
        expected = [
          "WORLD"
          "world"
        ];
      }
    );

    test-named-provider-with-into-fn = denTest (
      {
        den,
        lib,
        funnyNames,
        ...
      }:
      {
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ who ];
            }
          )
        ];
        den.schema.yell.includes = [ ];
        den.schema.size.includes = [ ];
        den.schema.num.includes = [ ];
        den.policies.test-greet-to-yell-fn = {
          from = "greet";
          to = "yell";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { shout = lib.toUpper ctx.who; } ];
          aspects = [
            (
              { shout }:
              {
                funny.names = [ shout ];
              }
            )
          ];
        };
        den.policies.test-greet-to-size = {
          from = "greet";
          to = "size";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { length = lib.stringLength ctx.who; } ];
          aspects = [
            (
              { length }:
              {
                funny.names = [ (lib.toString length) ];
              }
            )
          ];
        };
        den.policies.test-greet-to-num = {
          from = "greet";
          to = "num";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { number = lib.stringLength ctx.who; } ];
          aspects = [
            (
              { number }:
              {
                funny.names = [ ("num:" + lib.toString number) ];
              }
            )
          ];
        };
        den.default.policies = [
          "test-greet-to-yell-fn"
          "test-greet-to-size"
          "test-greet-to-num"
        ];

        expr = funnyNames (den.lib.resolveEntity "greet" { who = "world"; });
        expected = [
          "5"
          "WORLD"
          "num:5"
          "world"
        ];
      }
    );

  };
}
