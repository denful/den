{ den, ... }:
{
  den.schema.flake-parts.includes = [ den.policies.to-flake-parts-packages ];
}
