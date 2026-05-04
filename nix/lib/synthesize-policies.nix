# Policy scope and argument checking utilities.
{ lib, ... }:
let
  # Check if policy.resolve's required args are present in ctx.
  # Policies with { system, ... }: won't fire with empty ctx.
  # Policies with _: or { ... }: fire with any ctx.
  resolveArgsSatisfied =
    policy: ctx:
    if !lib.isFunction policy then
      false
    else
      let
        fargs = lib.functionArgs policy;
        requiredArgs = builtins.filter (k: !fargs.${k}) (builtins.attrNames fargs);
      in
      builtins.all (k: ctx ? ${k}) requiredArgs;

in
{
  inherit
    resolveArgsSatisfied
    ;
}
