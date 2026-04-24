# Flake output policies — traversal from flake-level entity kinds.
#
# Scope guard handled by synthesize-policies.nix: flake-* policies
# only fire when no entity attrset values are in context.
{
  den,
  lib,
  ...
}:
let
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
      _core = true;
      from = "flake-system";
      to = "flake-${output}";
      resolve =
        { system, ... }:
        lib.singleton {
          inherit system output;
        };
    };
  }) systemOutputs;
in
{
  den.policies = lib.listToAttrs systemOutputPolicies // {
    flake-to-flake-system = {
      _core = true;
      from = "flake";
      to = "flake-system";
      resolve = _: map (system: { inherit system; }) den.systems;
    };

    flake-system-to-flake-os = {
      _core = true;
      from = "flake-system";
      to = "flake-os";
      resolve =
        { system, ... }: map (host: { inherit host; }) (builtins.attrValues (den.hosts.${system} or { }));
    };

    flake-system-to-flake-hm = {
      _core = true;
      from = "flake-system";
      to = "flake-hm";
      resolve =
        { system, ... }: map (home: { inherit home; }) (builtins.attrValues (den.homes.${system} or { }));
    };
  };
}
