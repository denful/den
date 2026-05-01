{ den, ... }:
let
  inherit (den.lib.policy) resolve;
in
{

  # Read flake-parts classes from hosts and their includes
  den.schema.flake-parts.policies.to-host =
    _:
    map (host: resolve.to "host" { inherit host; }) (
      builtins.concatMap builtins.attrValues (builtins.attrValues den.hosts)
    );

}
