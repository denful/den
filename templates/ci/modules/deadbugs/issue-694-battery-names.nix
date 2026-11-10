# A battery's name is its identity, so distinct arguments give distinct
# names and the same arguments one name (den.lib.argsName). Argument lists
# that are sets to the battery (users, package names) don't depend on order.
{ denTest, lib, ... }:
let
  stateOf =
    den: host:
    (den.lib.aspects.resolveWithState "nixos" (den.lib.resolveEntity "host" { inherit host; })).state;
  registered =
    den: host: prefix:
    builtins.filter (lib.hasPrefix prefix) (
      lib.concatMap (s: map (k: lib.last (lib.splitString "/" k)) (builtins.attrNames s)) (
        builtins.attrValues (((stateOf den host).scopedAspectPolicies or (_: { })) null)
      )
    );
in
{
  flake.tests.deadbugs.issue-694-battery-names = {

    # A user named `all` is not every user.
    test-user-named-all-is-not-the-bare-battery = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          all = { };
          tux = { };
        };
        den.aspects.all.nixos.environment.etc.all.text = "x";
        den.aspects.tux.nixos.environment.etc.tux.text = "x";
        den.aspects.igloo.includes = [
          (den.batteries.user-aspects { users = [ "all" ]; })
          den.batteries.user-aspects
        ];
        expr = {
          all = igloo.environment.etc ? all;
          tux = igloo.environment.etc ? tux;
          names = lib.unique [
            (den.batteries.user-aspects { users = [ "all" ]; }).name
            den.batteries.user-aspects.name
          ];
        };
        expected = {
          all = true;
          tux = true;
          names = [
            ''user-aspects(["all"])''
            "user-aspects(all)"
          ];
        };
      }
    );
    # A comma in a user name is not a separator.
    test-comma-in-a-user-name-is-not-a-separator = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          "a,b" = { };
          a = { };
          b = { };
        };
        den.aspects."a,b".nixos.environment.etc.ab.text = "x";
        den.aspects.a.nixos.environment.etc.a.text = "x";
        den.aspects.b.nixos.environment.etc.b.text = "x";
        den.aspects.igloo.includes = [
          (den.batteries.user-aspects { users = [ "a,b" ]; })
          (den.batteries.user-aspects {
            users = [
              "a"
              "b"
            ];
          })
        ];
        expr = {
          ab = igloo.environment.etc ? ab;
          a = igloo.environment.etc ? a;
          b = igloo.environment.etc ? b;
        };
        expected = {
          ab = true;
          a = true;
          b = true;
        };
      }
    );
    # The same users in another order are the same battery: one name.
    test-user-order-is-one-battery = denTest (
      { den, ... }:
      {
        expr = {
          same =
            (den.batteries.user-aspects {
              users = [
                "a"
                "b"
              ];
            }).name == (den.batteries.user-aspects {
              users = [
                "b"
                "a"
                "a"
              ];
            }).name;
          distinct =
            (den.batteries.user-aspects { users = [ "a" ]; }).name != (den.batteries.user-aspects {
              users = [
                "a"
                "b"
              ];
            }).name;
        };
        expected = {
          same = true;
          distinct = true;
        };
      }
    );
    # Equal arguments registered from two places are one rule at a scope.
    test-equal-users-register-once = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          (den.batteries.user-aspects { users = [ "tux" ]; })
          den.aspects.extra
        ];
        den.aspects.extra.includes = [ (den.batteries.user-aspects { users = [ "tux" ]; }) ];
        expr = registered den config.den.hosts.x86_64-linux.igloo "user-aspects-accept(";
        expected = [ ''user-aspects-accept(["tux"])'' ];
      }
    );

    test-equal-unfree-sets-register-once = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.extra.includes = [
          (den.batteries.unfree [
            "q"
            "p"
          ])
        ];
        den.aspects.tux.includes = [
          (den.batteries.unfree [
            "p"
            "q"
          ])
          den.aspects.extra
        ];
        expr = registered den config.den.hosts.x86_64-linux.igloo "unfree-host(";
        expected = [ ''unfree-host(["p","q"])'' ];
      }
    );
    # unfree and insecure name their package sets the same way.
    test-unfree-names = denTest (
      { den, ... }:
      {
        expr = {
          comma =
            (den.batteries.unfree [ "a,b" ]).name != (den.batteries.unfree [
              "a"
              "b"
            ]).name;
          order =
            (den.batteries.unfree [
              "b"
              "a"
            ]).name == (den.batteries.unfree [
              "a"
              "b"
            ]).name;
        };
        expected = {
          comma = true;
          order = true;
        };
      }
    );
    test-insecure-names = denTest (
      { den, ... }:
      {
        expr = {
          comma =
            (den.batteries.insecure [ "a,b" ]).name != (den.batteries.insecure [
              "a"
              "b"
            ]).name;
          order =
            (den.batteries.insecure [
              "b"
              "a"
            ]).name == (den.batteries.insecure [
              "a"
              "b"
            ]).name;
        };
        expected = {
          comma = true;
          order = true;
        };
      }
    );
    # Both of two unfree sets reach the host.
    test-unfree-sets-both-land = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          (den.batteries.unfree [ "p,q" ])
          (den.batteries.unfree [
            "p"
            "q"
          ])
        ];
        expr = lib.sort builtins.lessThan igloo.unfree.packages;
        expected = [
          "p"
          "p,q"
          "q"
        ];
      }
    );
  };
}
