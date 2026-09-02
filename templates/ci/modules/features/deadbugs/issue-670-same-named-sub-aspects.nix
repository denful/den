# Issue #670: two unrelated aspects each declaring a same-named sub-aspect that
# delivers via `provides.to-users` — only one of the two lands, the other is
# silently dropped.
#
# Two independent collisions on one cause: an identity string built from a chain
# that had lost its head. `aspectSubmodule` handed its children a provider prefix
# read from the static `typeCfg`, but `providerType.merge` rewrites that chain on
# the value when it re-types an included nested aspect, so `alpha/tools` and
# `beta/tools` both gave their children the prefix ["tools"]. The two delivered
# aspects then shared one identity and gate dedup dropped one of them; the two
# cross-provide policies also shared one `scopedAspectPolicies` key and last-win
# dropped the other.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-670-same-named-sub-aspects = {

    test-same-named-sub-aspects = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha = {
          includes = [ den.aspects.alpha.tools ];
          tools.provides.to-users.homeManager.home.sessionVariables.ALPHA = "yes";
        };

        den.aspects.beta = {
          includes = [ den.aspects.beta.tools ];
          tools.provides.to-users.homeManager.home.sessionVariables.BETA = "yes";
        };

        expr = {
          alpha = tuxHm.home.sessionVariables.ALPHA or "<missing>";
          beta = tuxHm.home.sessionVariables.BETA or "<missing>";
        };
        expected = {
          alpha = "yes";
          beta = "yes";
        };
      }
    );

    # CONTROL: same shape, distinct sub-aspect names — reporter says this works.
    test-control-distinct-sub-aspect-names = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.alpha
          den.aspects.beta
        ];

        den.aspects.alpha = {
          includes = [ den.aspects.alpha.atools ];
          atools.provides.to-users.homeManager.home.sessionVariables.ALPHA = "yes";
        };

        den.aspects.beta = {
          includes = [ den.aspects.beta.btools ];
          btools.provides.to-users.homeManager.home.sessionVariables.BETA = "yes";
        };

        expr = {
          alpha = tuxHm.home.sessionVariables.ALPHA or "<missing>";
          beta = tuxHm.home.sessionVariables.BETA or "<missing>";
        };
        expected = {
          alpha = "yes";
          beta = "yes";
        };
      }
    );

  };
}
