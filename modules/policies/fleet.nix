# Fleet-to-hosts fan-out policy — resolves all hosts under the fleet entity scope.
{ lib, den, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  den.policies.fleet-to-hosts =
    {
      __entityKind ? null,
      ...
    }:
    if __entityKind != "fleet" then
      [ ]
    else
      lib.concatMap (
        system:
        map (hostName: resolve.to "host" { host = den.hosts.${system}.${hostName}; }) (
          builtins.attrNames (den.hosts.${system} or { })
        )
      ) (builtins.attrNames (den.hosts or { }));

  den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
}
