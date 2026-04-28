{ den, ... }:
let
  inherit (den.lib.policy) resolve;
in
{

  # Read flake-parts classes from hosts and their includes
  den.policies.flake-parts-to-host =
    {
      __entityKind ? null,
      ...
    }:
    if __entityKind != "flake-parts" then
      [ ]
    else
      map (host: resolve.to "host" { inherit host; }) (
        builtins.concatMap builtins.attrValues (builtins.attrValues den.hosts)
      );

}
