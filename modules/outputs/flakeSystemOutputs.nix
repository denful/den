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
      # Use the target entity if it has content (user set den.entityIncludes.flake-packages).
      entityIncs = den.entityIncludes."flake-${output}" or [ ];
      hasEntityContent = entityIncs != [ ];
      source =
        if hasEntityContent then
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

in
{
  # Cross-provides on flake-system: transition handler uses these when
  # policies route flake-system → flake-${output}.
  den.entityProvides.flake-system = lib.listToAttrs (
    map (output: {
      name = "flake-${output}";
      value = _: systemOutputFwd;
    }) outputs
  );
}
