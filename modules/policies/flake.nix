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
      _core = true;
      from = "flake-system";
      to = "flake-${output}";
      __functor =
        _:
        { system, ... }:
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
      _core = true;
      from = "flake";
      to = "flake-system";
      __functor = _: _: map (system: resolve { inherit system; }) den.systems;
    };

    flake-system-to-flake-os = {
      _core = true;
      from = "flake-system";
      to = "flake-os";
      __functor =
        _:
        { system, ... }:
        let
          hosts = den.hosts.${system} or { };
        in
        lib.concatMap (host: [
          (resolve { inherit host; })
          (include den.aspects."flake-os")
        ]) (builtins.attrValues hosts);
    };

    flake-system-to-flake-hm = {
      _core = true;
      from = "flake-system";
      to = "flake-hm";
      __functor =
        _:
        { system, ... }:
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
