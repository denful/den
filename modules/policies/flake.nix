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

  # flake → flake-system: fan out per system
  den.policies.flake-to-systems =
    _: map (system: resolve.to "flake-system" { inherit system; }) den.systems;

  # flake-system → host: resolve OS outputs
  den.policies.system-to-os-outputs =
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

  # flake-system → home: resolve HM outputs
  den.policies.system-to-hm-outputs =
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

  # Per-output route policies: class → flake
  den.policies.packages-to-flake = mkOutputPolicy "packages";
  den.policies.apps-to-flake = mkOutputPolicy "apps";
  den.policies.checks-to-flake = mkOutputPolicy "checks";
  den.policies.devShells-to-flake = mkOutputPolicy "devShells";
  den.policies.legacyPackages-to-flake = mkOutputPolicy "legacyPackages";

  den.schema.flake.includes = [ den.policies.flake-to-systems ];
  den.schema.flake-system.includes = [
    den.policies.system-to-os-outputs
    den.policies.system-to-hm-outputs
  ]
  ++ map (output: den.policies."${output}-to-flake") systemOutputs;
}
