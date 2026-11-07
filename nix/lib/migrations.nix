# Migration windows (#694). Each ends on its removal date: a scheduled release
# then removes the migration and leaves its flag as a throwing stub for one
# release. One date, read by every message and the docs.
{ config, ... }:
{
  removalDate = "2027-01-01";

  # The transition defaults (user-aspects and mutual-provider on every host)
  # apply until the owner acknowledges the migration; den's own suite turns
  # them off to test the end state.
  # `or`: den used as a library evaluates without these options.
  transitionActive =
    (config.den.internal.transitionDefaults or true)
    && !(config.den.migrations.user-host-content.acknowledged or false);
}
