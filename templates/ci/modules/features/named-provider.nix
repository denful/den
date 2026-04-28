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
        den.policies.test-greet-to-other =
          {
            __entityKind ? null,
            ...
          }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          if __entityKind != "greet" || !(ctx ? who) then
            [ ]
          else
            [
              (resolve.to "other" ctx)
              (include (
                { who }:
                {
                  funny.names = [ "other-${who}" ];
                }
              ))
            ];
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
        den.policies.test-greet-to-yell =
          {
            __entityKind ? null,
            ...
          }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          if __entityKind != "greet" || !(ctx ? who) then
            [ ]
          else
            [
              (resolve.to "yell" { shout = lib.toUpper ctx.who; })
              (include (
                { shout }:
                {
                  funny.names = [ shout ];
                }
              ))
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
        den.policies.test-greet-to-yell-fn =
          {
            __entityKind ? null,
            ...
          }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          if __entityKind != "greet" || !(ctx ? who) then
            [ ]
          else
            [
              (resolve.to "yell" { shout = lib.toUpper ctx.who; })
              (include (
                { shout }:
                {
                  funny.names = [ shout ];
                }
              ))
            ];
        den.policies.test-greet-to-size =
          {
            __entityKind ? null,
            ...
          }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          if __entityKind != "greet" || !(ctx ? who) then
            [ ]
          else
            [
              (resolve.to "size" { length = lib.stringLength ctx.who; })
              (include (
                { length }:
                {
                  funny.names = [ (lib.toString length) ];
                }
              ))
            ];
        den.policies.test-greet-to-num =
          {
            __entityKind ? null,
            ...
          }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          if __entityKind != "greet" || !(ctx ? who) then
            [ ]
          else
            [
              (resolve.to "num" { number = lib.stringLength ctx.who; })
              (include (
                { number }:
                {
                  funny.names = [ ("num:" + lib.toString number) ];
                }
              ))
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
