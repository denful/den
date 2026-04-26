{ denTest, ... }:
{
  flake.tests.ctx-named-provider = {

    test-self-named-provider = denTest (
      { den, funnyNames, ... }:
      {
        den.entityIncludes.greet = [
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
        den.entityIncludes.greet = [
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
        den.entityIncludes.greet = [
          (
            { who }:
            {
              funny.names = [ "hello-${who}" ];
            }
          )
        ];

        den.policies.test-greet-to-other = {
          from = "greet";
          to = "other";
          resolve = ctx: if !(ctx ? who) then [ ] else lib.singleton ctx;
        };
        den.default.policies = [ "test-greet-to-other" ];
        den.entityProvides.greet.other =
          _:
          { who }:
          {
            funny.names = [ "other-${who}" ];
          };

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
        den.entityIncludes.greet = [
          (
            { who }:
            {
              funny.names = [ who ];
            }
          )
        ];
        den.policies.test-greet-to-yell = {
          from = "greet";
          to = "yell";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { shout = lib.toUpper ctx.who; } ];
        };
        den.default.policies = [ "test-greet-to-yell" ];

        den.entityIncludes.yell = [
          (
            { shout }:
            {
              funny.names = [ shout ];
            }
          )
        ];

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
        den.entityIncludes.greet = [
          (
            { who }:
            {
              funny.names = [ who ];
            }
          )
        ];
        den.policies.test-greet-to-yell-fn = {
          from = "greet";
          to = "yell";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { shout = lib.toUpper ctx.who; } ];
        };
        den.policies.test-greet-to-size = {
          from = "greet";
          to = "size";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { length = lib.stringLength ctx.who; } ];
        };
        den.policies.test-greet-to-num = {
          from = "greet";
          to = "num";
          resolve = ctx: if !(ctx ? who) then [ ] else [ { number = lib.stringLength ctx.who; } ];
        };
        den.default.policies = [
          "test-greet-to-yell-fn"
          "test-greet-to-size"
          "test-greet-to-num"
        ];

        den.entityIncludes.yell = [
          (
            { shout }:
            {
              funny.names = [ shout ];
            }
          )
        ];

        den.entityIncludes.size = [
          (
            { length }:
            {
              funny.names = [ (lib.toString length) ];
            }
          )
        ];

        den.entityProvides.greet.num =
          _:
          { number }:
          {
            funny.names = [ ("num:" + lib.toString number) ];
          };

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
