# Inert compatibility shim. Cross-entity routing (to-users, to-hosts, named
# targets) is now built into emitAspectPolicies. Users who include
# den.batteries.mutual-provider in their defaults don't break — this evaluates to an
# inert aspect that produces no effects.
{ ... }:
{
  den.batteries.mutual-provider = {
    name = "mutual-provider";
    description = "Inert compat shim — cross-entity routing is built-in.";
    __functor = _: _: {
      name = "mutual-provider";
      description = "Inert compat shim.";
    };
  };
}
