# A raw-ref exclude naming a policy den never found must say so.
#
# The two cells disagree on purpose. The diagnostic is GLOBAL — "this reference
# matched no claim anywhere in the run" — because an exclude that resolves in
# one scope and not another is CORRECT behaviour, not a user error. The control
# below is the whole reason the check cannot sit on the per-scope dispatch path:
# it holds a host-scope exclude whose policy is claimed only under one of two
# users, so isPolicyExcluded genuinely answers true at one scope and false at
# the other, and nothing may warn about it.
{ denTest, ... }:
let
  # The finished pipeline state for igloo — the terminal registries the
  # diagnostic reads, same shape resolve.nix's post-assembly sees.
  hostState =
    den:
    let
      fxLib = den.lib.aspects.fx;
      hostRoot = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
    in
    (fxLib.pipeline.fxFullResolve {
      class = "nixos";
      ctx = fxLib.aspect.ctxFromHandlers (hostRoot.__scopeHandlers or { });
      self = den.lib.aspects.normalizeRoot hostRoot;
    }).state;
in
{
  flake.tests.unmatched-policy-exclude = {

    test-exclude-naming-unregistered-policy-warns = denTest (
      { den, ... }:
      let
        hostRoot = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.never-registered = _: [
          (den.lib.policy.include { nixos.environment.variables.MARKER = "yes"; })
        ];
        den.aspects.igloo.excludes = [ den.policies.never-registered ];

        expr = {
          messages = den.lib.aspects.fx.handlers.unmatchedRawRefExcludes (hostState den);
          # Forces the wired production path so the warning actually reaches
          # stderr; the message text itself is asserted above.
          resolves = (den.lib.aspects.resolve "nixos" hostRoot).imports != [ ];
        };
        expected = {
          messages = [
            "den: exclude in aspect 'igloo' names policy 'never-registered', which never registered in this resolution — the exclude suppresses nothing"
          ];
          resolves = true;
        };
      }
    );

    # The live control. tux claims the policy, pingu does not; the exclude is
    # declared once at host scope and reaches both. Excluded at tux, not at
    # pingu — and silent.
    test-exclude-matching-only-one-scope-is-silent = denTest (
      { den, ... }:
      let
        handlers = den.lib.aspects.fx.handlers;
        st = hostState den;
        scopes = builtins.attrNames (st.scopeContexts null);
        scopeMatching = pat: builtins.head (builtins.filter (s: builtins.match pat s != null) scopes);
        excludedAt =
          scope:
          handlers.isPolicyExcluded st scope (handlers.scopedConstraintsForScope st scope) "add-marker";
      in
      {
        den.hosts.x86_64-linux.igloo.users.pingu = { };
        den.hosts.x86_64-linux.igloo.users.tux.aspect.includes = [ den.policies.add-marker ];
        den.policies.add-marker = _: [
          (den.lib.policy.include { homeManager.programs.git.enable = true; })
        ];
        den.aspects.igloo.excludes = [ den.policies.add-marker ];

        expr = {
          atTux = excludedAt (scopeMatching ".*user=tux.*");
          atPingu = excludedAt (scopeMatching ".*user=pingu.*");
          messages = handlers.unmatchedRawRefExcludes st;
        };
        expected = {
          atTux = true;
          atPingu = false;
          messages = [ ];
        };
      }
    );
  };
}
