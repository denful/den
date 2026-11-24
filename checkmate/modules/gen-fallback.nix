# The gen helpers the user registry builds on, reached through den's built-in
# fallback: checkmate gives den no `gen` input, so `den.lib.schema.gen` comes
# from the gen pinned in templates/ci/flake.lock, as it does for a consumer.
{
  inputs,
  den,
  lib,
  ...
}:
let
  inherit (den.lib.schema) gen;
in
{
  flake.tests."test gen fallback path has no gen input" = {
    expr = inputs ? gen;
    expected = false;
  };

  flake.tests."test gen fallback priority bands" = {
    expr = map gen.merge.priorityBand [
      50
      75
      100
      999
      1000
      1499
      1500
    ];
    expected = [
      "force"
      "force"
      "set"
      "set"
      "default"
      "default"
      "unset"
    ];
  };

  flake.tests."test gen fallback layered fold" = {
    expr =
      map
        (
          strategy:
          (gen.algebra.record.foldLayersTraced {
            strategies.groups = strategy;
            layers = [
              { groups = [ "wheel" ]; }
              { groups = [ "video" ]; }
            ];
            layerNames = [
              "registry"
              "relation"
            ];
          }).value.groups
        )
        [
          den.lib.fold.replace
          den.lib.fold.append
        ];
    expected = [
      [ "video" ]
      [
        "wheel"
        "video"
      ]
    ];
  };

  # The condition terms of `den.users.<n>.hosts` (gen-algebra's term over
  # gen-identity's hashIdentity), decided on the fallback path.
  flake.tests."test gen fallback condition terms" = {
    expr =
      let
        inherit (den.lib) cond;
        ctx = {
          host.environment = "prod";
          user.groups = [ "admin" ];
        };
      in
      map (cond.decide "fallback" ctx) [
        (cond.eq [ "host" "environment" ] "prod")
        (cond.not (cond.eq [ "host" "environment" ] "prod"))
        (cond.all [
          (cond.eq [ "host" "environment" ] "prod")
          cond.always
        ])
        (cond.any [ (cond.eq [ "host" "environment" ] "dev") ])
      ];
    expected = [
      true
      false
      true
      false
    ];
  };

  # gen-identity's hash on the fallback path: equal for equal input,
  # different for different input, and the pinned gen's exact value for a
  # fixed input, so a stub that only prefixes can't pass.
  flake.tests."test gen fallback identity hash" = {
    expr =
      let
        h = v: gen.identity.hashIdentity "fallback" [ "a" ] (_: v);
      in
      [
        (h "x" == h "x")
        (h "x" == h "y")
        (h "x")
      ];
    expected = [
      true
      false
      "fallback:add83088391ed4cfd86f013529e87fbf515654e3e0f073b12ee30fd2d41acead"
    ];
  };
}
