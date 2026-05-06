# Flake output policies — activated via schema includes.
{
  den,
  lib,
  inputs,
  options,
  ...
}:
let
  inherit (den.lib.policy) resolve;

  systemOutputs = [
    "packages"
    "apps"
    "checks"
    "devShells"
    "legacyPackages"
  ];

  has-flake-output =
    output: ((options.flake.type.getSubOptions or (_: options.flake)) { }) ? ${output};

  mkOutputPolicy =
    output:
    { system, ... }:
    lib.optional (has-flake-output output) (
      den.lib.policy.route {
        fromClass = output;
        intoClass = "flake";
        path = [
          "flake"
          output
          system
        ];
        adaptArgs = _: { pkgs = inputs.nixpkgs.legacyPackages.${system}; };
      }
    );
in
{
  # Register system output names as classes so aspect keys dispatch correctly.
  den.classes = lib.listToAttrs (
    map (output: {
      name = output;
      value.description = "Flake ${output} output class";
    }) systemOutputs
  );

  # All policies defined as individual attributes.
  # flake -> flake-system: fan out per system
  den.policies.to-systems =
    _: map (system: resolve.to "flake-system" { inherit system; }) den.systems;

  # flake-system -> OS/HM outputs
  den.policies.to-os-outputs =
    { system, ... }:
    let
      hosts = den.hosts.${system} or { };
    in
    lib.concatMap (
      host:
      lib.optionals (host.intoAttr != [ ]) [
        (resolve.to "host" { inherit host; })
        (den.lib.policy.instantiate host)
      ]
    ) (builtins.attrValues hosts);

  den.policies.to-hm-outputs =
    { system, ... }:
    let
      homes = den.homes.${system} or { };
    in
    lib.concatMap (
      home:
      lib.optionals (home.intoAttr != [ ]) [
        (resolve.to "home" { inherit home; })
        (den.lib.policy.instantiate home)
      ]
    ) (builtins.attrValues homes);

  # Per-output route policies
  den.policies.to-packages = mkOutputPolicy "packages";
  den.policies.to-apps = mkOutputPolicy "apps";
  den.policies.to-checks = mkOutputPolicy "checks";
  den.policies.to-devShells = mkOutputPolicy "devShells";
  den.policies.to-legacyPackages = mkOutputPolicy "legacyPackages";

  den.schema.flake.includes = [ den.policies.to-systems ];
  den.schema.flake-system.includes = [
    den.policies.to-os-outputs
    den.policies.to-hm-outputs
  ]
  ++ map (output: den.policies."to-${output}") systemOutputs;
}
