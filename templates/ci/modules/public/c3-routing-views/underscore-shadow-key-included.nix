# `_` is a total alias for `provides`, not a filtered view of it. Before the
# three `_` constructions in types.nix were unified behind one `mkUnderscore`,
# A (root) and B (functor-carrying batteries) excluded a key held both as a
# direct child and as a provides child from `_`'s includes, while C (nested
# freeform keys) included it — three constructions of one alias silently
# disagreeing, and nothing in CI asserted either answer.
#
# Ruling: include it, via its direct value. Excluding it would make `_` a
# filtered view of `provides` under one name — the defect class den has spent
# a week removing. This pins that ruling at all three construction sites so a
# future drift back to exclusion is caught rather than silently reintroduced.
{ denTest, ... }:
{
  flake.tests.deadbugs.underscore-shadow-key-included = {

    # Site A: root aspect (mergeWithAspectMeta).
    test-shadow-key-included-via-underscore-root = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.shadowRoot = {
          provides.shadow.nixos.environment.etc."prov-root".text = "y";
          shadow.nixos.environment.etc."direct-root".text = "y";
        };

        den.aspects.igloo.includes = [ den.aspects.shadowRoot._ ];

        expr = {
          direct = igloo.environment.etc ? "direct-root";
          prov = igloo.environment.etc ? "prov-root";
        };
        expected = {
          direct = true;
          prov = false;
        };
      }
    );

    # Site B: functor-carrying battery (mergeFunctions' functor branch).
    test-shadow-key-included-via-underscore-battery = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.battHolder.provides.shadowBatt = {
          __functor = self: args: { };
          shadow.nixos.environment.etc."direct-batt".text = "y";
          _.shadow.nixos.environment.etc."prov-batt".text = "y";
        };

        den.aspects.igloo.includes = [ den.aspects.battHolder.shadowBatt._ ];

        expr = {
          direct = igloo.environment.etc ? "direct-batt";
          prov = igloo.environment.etc ? "prov-batt";
        };
        expected = {
          direct = true;
          prov = false;
        };
      }
    );

    # Site C: nested freeform key (aspectContentType).
    test-shadow-key-included-via-underscore-nested = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.shadowNested.holder = {
          provides.shadow.nixos.environment.etc."prov-nested".text = "y";
          shadow.nixos.environment.etc."direct-nested".text = "y";
        };

        den.aspects.igloo.includes = [ den.aspects.shadowNested.holder._ ];

        expr = {
          direct = igloo.environment.etc ? "direct-nested";
          prov = igloo.environment.etc ? "prov-nested";
        };
        expected = {
          direct = true;
          prov = false;
        };
      }
    );

  };
}
