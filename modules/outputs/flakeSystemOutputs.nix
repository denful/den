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
    {
      system,
      output,
      class,
      aspect-chain,
    }:
    let
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
  # Register forwarders as named aspects.
  den.aspects = lib.listToAttrs (
    map (output: {
      name = "flake-${output}";
      value = systemOutputFwd;
    }) outputs
  );

  # Entity registrations: flake-system must exist as an entity for
  # flake-to-flake-system transitions. Per-output entities (flake-packages etc.)
  # must exist for flake-system-to-flake-* transitions.
  den.entityIncludes =
    lib.listToAttrs (
      map (output: {
        name = "flake-${output}";
        value = [ ];
      }) outputs
    )
    // {
      flake-system = [ ];
    };
}
