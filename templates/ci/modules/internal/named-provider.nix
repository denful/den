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
        den.schema.other.includes = [ ];
        den.policies.test-greet-to-other =
          { who, ... }@ctx:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "other" ctx)
            (include (
              { who }:
              {
                funny.names = [ "other-${who}" ];
              }
            ))
          ];
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ "hello-${who}" ];
            }
          )
          den.policies.test-greet-to-other
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
        den.schema.yell.includes = [ ];
        den.policies.test-greet-to-yell =
          { who, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "yell" { shout = lib.toUpper who; })
            (include (
              { shout }:
              {
                funny.names = [ shout ];
              }
            ))
          ];
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ who ];
            }
          )
          den.policies.test-greet-to-yell
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
        den.schema.yell.includes = [ ];
        den.schema.size.includes = [ ];
        den.schema.num.includes = [ ];
        den.policies.test-greet-to-yell-fn =
          { who, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "yell" { shout = lib.toUpper who; })
            (include (
              { shout }:
              {
                funny.names = [ shout ];
              }
            ))
          ];
        den.policies.test-greet-to-size =
          { who, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "size" { length = lib.stringLength who; })
            (include (
              { length }:
              {
                funny.names = [ (lib.toString length) ];
              }
            ))
          ];
        den.policies.test-greet-to-num =
          { who, ... }:
          let
            inherit (den.lib.policy) resolve include;
          in
          [
            (resolve.to "num" { number = lib.stringLength who; })
            (include (
              { number }:
              {
                funny.names = [ ("num:" + lib.toString number) ];
              }
            ))
          ];
        den.schema.greet.includes = [
          (
            { who }:
            {
              funny.names = [ who ];
            }
          )
          den.policies.test-greet-to-yell-fn
          den.policies.test-greet-to-size
          den.policies.test-greet-to-num
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
