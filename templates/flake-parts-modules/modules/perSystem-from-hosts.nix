{ den, ... }:
{

  # Read flake-parts classes from hosts and their includes
  den.ctx.flake-parts.into.host =
    _:
    map (host: { inherit host; }) (
      builtins.concatMap builtins.attrValues (builtins.attrValues den.hosts)
    );

}
