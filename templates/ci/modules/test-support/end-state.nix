# den's suite tests #694's end state: the transition defaults (user-aspects
# and mutual-provider on every host, until den.lib.migrations.removalDate) are
# off for every cell. deadbugs/issue-694-migration.nix turns them back on.
{
  denTest.den.internal.transitionDefaults = false;
}
