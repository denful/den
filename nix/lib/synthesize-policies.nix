# Policy scope and argument checking utilities.
{
  lib,
  den,
  ...
}:
let
  # Check if policy.resolve's required args are present in ctx.
  # Policies with { system, ... }: won't fire with empty ctx.
  # Policies with _: or { ... }: fire with any ctx.
  resolveArgsSatisfied =
    policy: ctx:
    let
      inherit (den.lib.policyTypes) policyFnArgs;
      fargs = policyFnArgs policy;
      requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
      # Trait names are satisfiable — traits get merged into resolve context
      # by policy-dispatch before calling policy.resolve.
      traitNames = den.traits or { };
      requiredArgSatisfied = k: ctx ? ${k} || traitNames ? ${k};
    in
    builtins.all requiredArgSatisfied requiredArgs;

in
{
  inherit
    resolveArgsSatisfied
    ;
}
