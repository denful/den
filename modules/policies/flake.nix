# Flake output policies — traversal from flake-level entity kinds.
#
# Policies use __entityKind body guards for scoping and resolve.to
# for targetKey derivation (resolve binding keys don't match schema
# kind names — e.g. `host` resolves to `flake-os`).
{
  den,
  lib,
  ...
}:
let
  inherit (den.lib.policy) resolve include;

  systemOutputs = [
    "packages"
    "apps"
    "checks"
    "devShells"
    "legacyPackages"
  ];

  systemOutputPolicies = map (output: {
    name = "flake-system-to-flake-${output}";
    value =
      {
        __entityKind ? null,
        system,
        ...
      }:
      if __entityKind != "flake-system" then
        [ ]
      else
        [
          (resolve.to "flake-${output}" { inherit system output; })
          (include den.aspects."flake-${output}")
        ];
  }) systemOutputs;
in
{
  den.policies = lib.listToAttrs systemOutputPolicies // {
    flake-to-flake-system =
      {
        __entityKind ? null,
        ...
      }:
      if __entityKind != "flake" then
        [ ]
      else
        map (system: resolve.to "flake-system" { inherit system; }) den.systems;

    flake-system-to-flake-os =
      {
        __entityKind ? null,
        system,
        ...
      }:
      if __entityKind != "flake-system" then
        [ ]
      else
        let
          hosts = den.hosts.${system} or { };
        in
        lib.concatMap (host: [
          (resolve.to "flake-os" { inherit host; })
          (include den.aspects."flake-os")
        ]) (builtins.attrValues hosts);

    flake-system-to-flake-hm =
      {
        __entityKind ? null,
        system,
        ...
      }:
      if __entityKind != "flake-system" then
        [ ]
      else
        let
          homes = den.homes.${system} or { };
        in
        lib.concatMap (home: [
          (resolve.to "flake-hm" (
            {
              inherit home;
            }
            // lib.optionalAttrs (home.host != null) { inherit (home) host; }
            // lib.optionalAttrs (home.user != null) { inherit (home) user; }
          ))
          (include den.aspects."flake-hm")
        ]) (builtins.attrValues homes);
  };
}
