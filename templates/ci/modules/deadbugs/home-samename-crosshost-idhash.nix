# Regression: two STANDALONE homes sharing a username but bound to different
# hosts (`user@hostA`, `user@hostB`) hashed to an identical `id_hash`.
#
# A home's public `name` is force-set to the bare user name, so it cannot
# distinguish these homes. Identity is instead keyed on `__scopeName` (the
# registry key, e.g. `user@hostA`) plus `system` via `_identity.keys` (see
# nix/lib/entities/home.nix), never on reflected, user-overridable presentation
# fields like `description`.
{ denTest, ... }:
{
  flake.tests.home-samename-crosshost-idhash = {

    # Same username, different host binding: id_hash must differ.
    test-crosshost-distinct-id-hash = denTest (
      { den, ... }:
      {
        den.homes.aarch64-darwin."someuser@hostA" = { };
        den.homes.aarch64-darwin."someuser@hostB" = { };

        expr =
          den.homes.aarch64-darwin."someuser@hostA".id_hash
          == den.homes.aarch64-darwin."someuser@hostB".id_hash;
        expected = false;
      }
    );

    # The same registry key on different systems is also a distinct home.
    test-cross-system-distinct-id-hash = denTest (
      { den, ... }:
      {
        den.homes.aarch64-darwin."someuser@hostA" = { };
        den.homes.x86_64-linux."someuser@hostA" = { };

        expr =
          den.homes.aarch64-darwin."someuser@hostA".id_hash
          == den.homes.x86_64-linux."someuser@hostA".id_hash;
        expected = false;
      }
    );

  };
}
