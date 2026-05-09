{ den, ... }:
let
  inherit (den.lib.policy) resolve;
in
{

  # Read flake-parts classes from hosts and their includes
  den.policies.flake-parts-to-host =
    _:
    map (host: resolve.to "host" { inherit host; }) (
      builtins.concatMap builtins.attrValues (builtins.attrValues den.hosts)
    );
  den.schema.flake-parts.includes = [ den.policies.flake-parts-to-host ];

}
