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
      source = lib.head aspect-chain;
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

}
