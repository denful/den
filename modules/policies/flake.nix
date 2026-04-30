# Flake output policies — schema-scoped, no __entityKind guards.
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
in
{
  # Register system output names as classes so aspect keys dispatch correctly.
  den.classes = lib.listToAttrs (
    map (output: {
      name = output;
      value.description = "Flake ${output} output class";
    }) systemOutputs
  );

  # flake -> flake-system: fan out per system
  den.schema.flake.policies.to-systems =
    _: map (system: resolve.to "flake-system" { inherit system; }) den.systems;

  # flake-system -> OS/HM outputs + per-output routes
  den.schema.flake-system.policies = {
    to-os-outputs =
      { system, ... }:
      let
        hosts = den.hosts.${system} or { };
      in
      lib.concatMap (host: lib.optional (host.intoAttr != [ ]) (den.lib.policy.instantiate host)) (
        builtins.attrValues hosts
      );

    to-hm-outputs =
      { system, ... }:
      let
        homes = den.homes.${system} or { };
      in
      lib.concatMap (home: lib.optional (home.intoAttr != [ ]) (den.lib.policy.instantiate home)) (
        builtins.attrValues homes
      );
  }
  // lib.listToAttrs (
    map (output: {
      name = "to-${output}";
      value =
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
    }) systemOutputs
  );
}
