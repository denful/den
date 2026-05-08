# Terranix integration via per-host route into flake-parts.
#
# Each host scope's route collects only its own terranix class modules
# and delivers them into terranixConfigurations.<host.name>.
#
# terranix's flake-module handles all output generation:
#   nix run .#<host>           — tofu apply
#   nix run .#<host>.plan      — tofu plan
#   nix run .#<host>.destroy   — tofu destroy
#   nix develop .#<host>       — shell with tofu + scripts
{ den, inputs, ... }:
let
  inherit (den.lib.policy) resolve route;
  perSystemModule = den.lib.aspects.resolveImports "flake-parts" (
    den.lib.resolveEntity "flake-parts" { }
  );
in
{
  imports = [ inputs.terranix.flakeModule ];

  den.classes.terranix = { };
  den.classes.flake-parts = { };

  # Walk hosts in the flake-parts entity so per-host routes fire.
  den.policies.flake-parts-to-host =
    _:
    map (host: resolve.to "host" { inherit host; }) (
      builtins.concatMap builtins.attrValues (builtins.attrValues den.hosts)
    );

  # Per-host: collect terranix class from host subtree → terranixConfigurations.<name>
  den.policies.terranix-per-host =
    { host, ... }:
    [
      (route {
        fromClass = "terranix";
        intoClass = "flake-parts";
        path = [
          "terranix"
          "terranixConfigurations"
          host.name
        ];
        instantiate =
          { modules, ... }:
          {
            inherit modules;
          };
      })
    ];

  den.schema.flake-parts.includes = [ den.policies.flake-parts-to-host ];
  den.schema.host.includes = [ den.policies.terranix-per-host ];

  perSystem.imports = [ perSystemModule ];
}
