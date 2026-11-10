# A policy registered by two entities a scope binds out of its tree (an
# environment and a region a guest rebinds) fires once per instance at that
# scope, whichever of them resolves after the binder. Reported in an external
# review; the late dispatch re-pass offered it again without the late firing.
# One record registered at both fires once; two records sharing a name (`p`)
# are two policies and both fire, in every order.
{ denTest, lib, ... }:
let
  fixture =
    {
      den,
      config,
      devFirst,
      regionFirst,
    }:
    let
      env = name: {
        inherit name;
        aspect = den.aspects."${name}-env";
        id_hash = "environment:${name}";
      };
      prod = env "prod";
      dev = env "dev";
      r1 = {
        name = "r1";
        aspect = den.aspects.r1-region;
        id_hash = "region:r1";
      };
      guest = config.den.hosts.x86_64-linux.cuda // {
        intoAttr = [ ];
      };
      km =
        tag:
        { host, user, ... }:
        [
          (den.lib.policy.provide {
            class = "nixos";
            module.boot.kernelModules = [ "${tag}-${user.name}" ];
          })
        ];
    in
    {
      den.schema.environment.isEntity = true;
      den.schema.region.isEntity = true;
      den.schema.host.parent = "environment";
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.x86_64-linux.cuda = {
        intoAttr = [ ];
        users = {
          pingu = { };
          gentoo = { };
        };
      };
      den.policies.to-env = _: [
        (den.lib.policy.resolve.to "environment" { environment = if devFirst then dev else prod; })
        (den.lib.policy.resolve.to "environment" { environment = if devFirst then prod else dev; })
      ];
      den.policies.to-region = _: [ (den.lib.policy.resolve.to "region" { region = r1; }) ];
      den.schema.flake.includes =
        if regionFirst then
          [
            den.policies.to-region
            den.policies.to-env
          ]
        else
          [
            den.policies.to-env
            den.policies.to-region
          ];
      den.policies.env-to-hosts =
        { environment, ... }:
        lib.optionals (environment.name == "prod") [
          (den.lib.policy.resolve.to "host" { host = den.hosts.x86_64-linux.igloo; })
          (den.lib.policy.instantiate den.hosts.x86_64-linux.igloo)
        ];
      den.schema.flake-system.excludes = [
        den.policies.system-to-os-outputs
        den.policies.system-to-hm-outputs
      ];
      den.schema.environment.includes = [ den.policies.env-to-hosts ];
      den.schema.guest-kind = {
        isEntity = true;
        parent = "host";
        includes = [ den.policies.host-to-users ];
      };
      den.policies.to-guest =
        { host, ... }:
        lib.optionals (host.name == "igloo") [
          (den.lib.policy.resolve.to "guest-kind" {
            guest-kind = guest;
            host = guest;
            environment = dev;
            region = r1;
          })
        ];
      den.schema.host.includes = [ den.policies.to-guest ];
      den.policies.same-pol = km "same";
      den.policies.dev-only = km "devonly";
      den.policies.reg-only = km "regonly";
      den.aspects.prod-env = { };
      den.aspects.dev-env.includes = [
        den.policies.same-pol
        den.policies.dev-only
        # Two records sharing the name `p`: two policies, both fire.
        (den.lib.policy.mkPolicy "p" (km "pa"))
      ];
      den.aspects.r1-region.includes = [
        den.policies.same-pol
        den.policies.reg-only
        (den.lib.policy.mkPolicy "p" (km "pb"))
      ];
    };
  cell =
    devFirst: regionFirst:
    denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [
          (fixture {
            inherit
              den
              config
              devFirst
              regionFirst
              ;
          })
        ];
        expr =
          let
            st = (den.lib.aspects.resolveWithState "nixos" (den.lib.resolveEntity "flake" { })).state;
          in
          lib.sort lib.lessThan (
            lib.concatMap (p: p.module.boot.kernelModules or [ ]) (
              lib.concatLists (builtins.attrValues ((st.scopedProvides or (_: { })) null))
            )
          );
        expected = lib.sort lib.lessThan [
          "devonly-gentoo"
          "devonly-pingu"
          "pa-gentoo"
          "pa-pingu"
          "pb-gentoo"
          "pb-pingu"
          "regonly-gentoo"
          "regonly-pingu"
          "same-gentoo"
          "same-pingu"
        ];
      }
    );
  # A registered record's `fn` slot: one record's slot taken twice compares
  # equal (registerPolicy keys late dispatch by it); a `{ inherit (r) fn; }`
  # copy doesn't, so the slot, not a copy, is what is compared.
  slotOf = builtins.intersectAttrs { fn = null; };
  sameFnRecords =
    den:
    let
      f = { host, user, ... }: [ ];
    in
    {
      one = den.lib.policy.mkPolicy "p" f;
      two = den.lib.policy.mkPolicy "p" f;
    };
in
{
  flake.tests.late-dispatch-bound-repass-once-slots = {
    test-one-record-slot-equal = denTest (
      { den, ... }:
      let
        r = den.policies.same-pol;
      in
      {
        imports = [
          {
            den.policies.same-pol = { host, user, ... }: [ ];
          }
        ];
        expr = {
          slot = slotOf r == slotOf r;
          copy = { inherit (r) fn; } == { inherit (r) fn; };
        };
        expected = {
          slot = true;
          copy = false;
        };
      }
    );
    # Two `mkPolicy "p" f` over one `f` are equal records, so one policy, as
    # the claim registry already rules (O5: one registration seen again).
    test-equal-records-one-policy = denTest (
      { den, ... }:
      let
        rs = sameFnRecords den;
      in
      {
        expr = {
          slot = slotOf rs.one == slotOf rs.two;
          record = rs.one == rs.two;
        };
        expected = {
          slot = true;
          record = true;
        };
      }
    );
  };
  flake.tests.late-dispatch-bound-repass-once = {
    test-dev-first-region-first = cell true true;
    test-dev-first-region-last = cell true false;
    test-dev-last-region-first = cell false true;
    test-dev-last-region-last = cell false false;
  };
}
