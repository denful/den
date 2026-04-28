# Flake output policies — traversal from flake-level entity kinds.
#
# Policies use __entityKind body guards for scoping and `to` for
# targetKey derivation (resolve binding keys don't match schema kind
# names).
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
    value = {
      to = "flake-${output}";
      __functor =
        _:
        {
          __entityKind ? null,
          system,
          ...
        }:
        if __entityKind != "flake-system" then
          [ ]
        else
          [
            (resolve { inherit system output; })
            (include den.aspects."flake-${output}")
          ];
    };
  }) systemOutputs;
in
{
  den.policies = lib.listToAttrs systemOutputPolicies // {
    flake-to-flake-system = {
      to = "flake-system";
      __functor =
        _:
        {
          __entityKind ? null,
          ...
        }:
        if __entityKind != "flake" then [ ] else map (system: resolve { inherit system; }) den.systems;
    };

    flake-system-to-flake-os = {
      to = "flake-os";
      __functor =
        _:
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
            (resolve { inherit host; })
            (include den.aspects."flake-os")
          ]) (builtins.attrValues hosts);
    };

    flake-system-to-flake-hm = {
      to = "flake-hm";
      __functor =
        _:
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
            (resolve { inherit home; })
            (include den.aspects."flake-hm")
          ]) (builtins.attrValues homes);
    };
  };
}
