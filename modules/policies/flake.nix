# Flake output policies — traversal from flake-level entity kinds.
#
# All policies retain `from` for entity-kind scoping and `to` for
# targetKey derivation (resolve binding keys don't match schema kind
# names). Removed: _core (new-style handler skips activation).
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
      from = "flake";
      to = "flake-system";
      __functor = _: _: map (system: resolve { inherit system; }) den.systems;
    };

    flake-system-to-flake-os = {
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
