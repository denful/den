# DEPRECATED: scheduled for removal after first stable release post-fx-pipeline merge.
# Migration: use cross-entity policies (policy.resolve, policy.include).
# Compatibility shim: makes den._.mutual-provider evaluate to an inert aspect
# instead of erroring. On main, mutual-provider was a parametric aspect that
# handled cross-entity routing via provides.X — that routing is now built-in
# via the provides-compat pipeline handler.
# Remove after migration period (see provides-removal spec).
{ lib, ... }:
{
  den.provides.mutual-provider =
    lib.warn
      "den.provides.mutual-provider is deprecated — cross-entity routing is now built-in via policies. Remove from includes."
      {
        name = "mutual-provider";
        description = "Deprecated compat shim — remove from includes.";
        # On main, mutual-provider was a parametric aspect. Some users may apply it
        # with arguments (den._.mutual-provider { ... }). The __functor accepts and
        # ignores any arguments to prevent hard errors.
        __functor = _: _: {
          name = "mutual-provider";
          description = "Deprecated compat shim.";
        };
      };
}
