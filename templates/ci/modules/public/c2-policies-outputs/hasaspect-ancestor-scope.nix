# Regression: projected (in-context) hasAspect under an ANCESTOR entity-kind
# scope.
#
# A host resolved under a fleet-style topology (flake → tier → host, where
# `tier` is an entity kind like an environment) inherits the `tier` binding in
# its production ctx. The projected hasAspect must still resolve against the
# owning host's bucket — which is produced by the host's OWN standalone run and
# knows nothing of the ancestor `tier`. Buckets are keyed by entity identity
# (`id_hash`), which is context-free (kind+name, not ancestry), so the consuming
# host looks itself up by its own id_hash regardless of any ancestor scopes —
# no scope-string reconstruction, no ancestor to strip. The historical bug
# (keying by a reconstructed "tier=prod,host=igloo" scope-string vs a bucket
# keyed "host=igloo") read false here and dropped agenix's /persist prefix
# (identityPaths → /etc/ssh). den's default flake→system→host walk hides it
# because `system` is a plain string, not an entity kind.
{ denTest, lib, ... }:
{
  flake.tests.hasaspect-ancestor-scope = {

    test-projected-hasaspect-under-ancestor-tier = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib.policy) resolve instantiate;
      in
      {
        # Insert an entity-kind `tier` between flake-system and host:
        # flake-system → tier → host. host.parent = tier makes tier an ANCESTOR.
        den.schema.tier.isEntity = true;
        den.schema.host.parent = "tier";
        den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
        den.policies.test-tier-walk = { system, ... }: [ (resolve.to "tier" { tier.name = "prod"; }) ];
        den.policies.test-tier-to-host =
          { system, ... }:
          lib.concatMap (
            host:
            lib.optionals (host.intoAttr != [ ]) [
              (resolve.to "host" { inherit host; })
              (instantiate host)
            ]
          ) (builtins.attrValues (den.hosts.${system} or { }));
        den.schema.flake-system.includes = [ den.policies.test-tier-walk ];
        den.schema.tier.includes = [ den.policies.test-tier-to-host ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        # transitively-included, settings-bearing, namespaced aspect (the
        # core.impermanence shape).
        den.aspects.svc.feature = {
          settings.opt = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          nixos = { };
        };
        den.aspects.role.includes = [ den.aspects.svc.feature ];
        den.aspects.igloo.includes = [ den.aspects.role ];
        den.hosts.x86_64-linux.igloo.settings.svc.feature.opt = true;

        # agenix-shape host-include that reads the PROJECTED host.hasAspect.
        den.schema.host.includes = [
          (
            { host, ... }:
            {
              nixos.environment.etc."has-feature".text = lib.boolToString (
                host.hasAspect den.aspects.svc.feature
              );
            }
          )
        ];

        expr = igloo.environment.etc."has-feature".text;
        expected = "true";
      }
    );

    # NON-host owner: the bucket-producing entity is a standalone `home` (NOT a
    # host — `host` is ABSENT from ctx), and the consumer is a child entity kind
    # `crew` (parent = home) the home fans out to. The home's standalone run
    # buckets the crew scope, re-keyed by crew's id_hash, with `svc/feature`
    # delivered into it. The crew include reads the PROJECTED crew.hasAspect,
    # which must resolve against the OWNING home's bucket — reached by walking
    # crew's parent chain (crew → home).
    #
    # The old hardcoded-`host`-literal lookup reads `rawScopedCtx.host`
    # (ABSENT) → crew's own binding (no `__pathSetByScope`: crew has no entity
    # submodule) → empty bucket → FALSE. The generic chain walk skips the
    # bucket-less `host` literal, ascends crew → home, finds the home's bucket
    # and the crew-keyed `svc/feature` → TRUE. This case is RED at HEAD before
    # the refactor and GREEN after.
    test-projected-hasaspect-non-host-owner = denTest (
      { den, config, ... }:
      let
        inherit (den.lib.policy) resolve;
      in
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];
        den.homes.x86_64-linux.tux = { };

        # crew nests inside home: home → crew. home is an ANCESTOR of crew.
        den.schema.crew.isEntity = true;
        den.schema.crew.parent = "home";

        # settings-bearing, namespaced aspect delivered to the CREW scope, so it
        # lands in the home's production bucket keyed by crew's id_hash.
        den.aspects.svc.feature = {
          settings.opt = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          homeManager = { };
        };
        den.schema.crew.includes = [
          den.aspects.svc.feature
          (
            { crew, ... }:
            {
              homeManager.home.sessionVariables.HAS_FEATURE = lib.boolToString (
                crew.hasAspect den.aspects.svc.feature
              );
            }
          )
        ];

        # Home fans out to a crew child. crew carries an explicit id_hash so the
        # bucket re-key (entities/_types.nix:pathSetByScopeOption) keys the crew
        # scope's delivered set by crew identity — what the projected lookup
        # reads — instead of a raw scope-string (crew has no instance registry).
        den.policies.test-home-to-crew =
          { home, ... }:
          [
            (resolve.to "crew" {
              crew = {
                name = home.name or "tux";
                id_hash = "crew-tux";
              };
            })
          ];
        den.schema.home.includes = [ den.policies.test-home-to-crew ];

        expr = config.flake.homeConfigurations.tux.config.home.sessionVariables.HAS_FEATURE or "MISSING";
        expected = "true";
      }
    );
  };
}
