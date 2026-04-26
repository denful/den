{
  den,
  lib,
  options,
  inputs,
  ...
}:
let
  has-flake-output =
    output: ((options.flake.type.getSubOptions or (_: options.flake)) { }) ? ${output};

  systemOutputFwd =
    { system, output }:
    { class, aspect-chain }:
    let
      # Use the target stage if it has content (user set den.stages.flake-packages).
      # Fall back to aspect-chain root for test/inline patterns where packages
      # class is on the root aspect directly.
      stageTarget = den.stages."flake-${output}" or null;
      hasStageContent =
        stageTarget != null
        && ((stageTarget.includes or [ ]) != [ ] || (stageTarget.provides or { }) != { });
      source =
        if hasStageContent then
          den.lib.resolveEntity "flake-${output}" { inherit system; }
        else
          lib.head aspect-chain;
    in
    den.provides.forward {
      each = lib.optional (class == "flake") output;
      fromClass = _: output;
      intoClass = _: "flake";
      intoPath = _: [
        "flake"
        output
        system
      ];
      guard = _: has-flake-output output;
      adaptArgs = _: { pkgs = inputs.nixpkgs.legacyPackages.${system}; };
      fromAspect = _: source;
    };

  outputs = [
    "packages"
    "apps"
    "checks"
    "devShells"
    "legacyPackages"
  ];

  stageSystemOuts = map (output: {
    flake-system.provides."flake-${output}" = _: systemOutputFwd;
  }) outputs;

in
{
  den.stages = lib.mkMerge stageSystemOuts;
}
