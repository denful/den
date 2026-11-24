# The gen helpers the user registry builds on, reached through den's built-in
# fallback: checkmate gives den no `gen` input, so `den.lib.schema.gen` comes
# from the gen pinned in templates/ci/flake.lock, as it does for a consumer.
{ inputs, den, ... }:
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
}
