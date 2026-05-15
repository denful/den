{ den, ... }:
{
  den.schema.flake-parts.includes = [ den.policies.packages-to-flake-parts ];
}
