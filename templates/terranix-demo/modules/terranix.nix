# Terranix integration: route terranix class through terranixConfiguration.
#
# The route collects terranix modules from all host scopes in the pipeline,
# calls terranixConfiguration to produce config.tf.json, and places the
# derivation at packages.<system>.tf.
#
# Build:   nix build .#packages.x86_64-linux.tf
# Inspect: nix build .#packages.x86_64-linux.tf && cat result
{ inputs, den, ... }:
{
  den.policies.to-terranix =
    { system, ... }:
    [
      (den.lib.policy.route {
        fromClass = "terranix";
        intoClass = "flake";
        path = [
          "flake"
          "packages"
          system
          "tf"
        ];
        instantiate =
          { modules, ... }:
          inputs.terranix.lib.terranixConfiguration {
            inherit system modules;
          };
      })
    ];

  den.schema.flake-system.includes = [ den.policies.to-terranix ];
}
