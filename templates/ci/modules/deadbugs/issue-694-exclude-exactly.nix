# #694 round 4, owner criterion: an exclude removes exactly the instances of
# the rule it names, no more and no fewer. Each form both as an aspect's
# `excludes` (L) and as a policy's `exclude` effect (E).
{ denTest, lib, ... }:
let
  # A { host } policy writing etc.<f> into the host.
  hp =
    den: n: f:
    den.lib.policy.mkPolicy n (
      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.${f}.text = "x"; }) ]
    );
  # A { host, user } policy delivering etc.<f> to the host.
  up =
    den: n: f:
    den.lib.policy.mkPolicy n (
      { host, user, ... }:
      [
        (den.lib.policy.provide {
          class = "nixos";
          receiver = host;
          module.environment.etc.${f}.text = "x";
        })
      ]
    );
  # Exclude X on igloo, as a list (L) or as a policy `exclude` effect (E).
  exL = x: { den.aspects.igloo.excludes = [ x ]; };
  exE = den: x: {
    den.aspects.igloo.includes = [
      (den.lib.policy.mkPolicy "do-exclude" ({ host, ... }: [ (den.lib.policy.exclude x) ]))
    ];
  };
  two = {
    den.hosts.x86_64-linux.igloo.users = {
      tux = { };
      pingu = { };
    };
  };
  has = igloo: f: igloo.environment.etc ? ${f};
  both = name: mk: {
    "test-${name}-L" = mk "L";
    "test-${name}-E" = mk "E";
  };
  ex =
    den: form: x:
    if form == "L" then exL x else exE den x;
in
{
  flake.tests.deadbugs.issue-694-exclude-exactly =
    # F1: two records named "g" on two users; exclude A.
    both "f1-same-name-other-scope" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = up den "g" "ga";
          b = up den "g" "gb";
        in
        {
          imports = [
            two
            (ex den form a)
          ];
          den.aspects.tux.includes = [ a ];
          den.aspects.pingu.includes = [ b ];
          expr = {
            ga = has igloo "ga";
            gb = has igloo "gb";
          };
          expected = {
            ga = false;
            gb = true;
          };
        }
      )
    )
    # F1d: both on tux (B displaced); exclude B, then exclude A.
    // both "f1d-displaced-exclude-second" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = up den "g" "ga";
          b = up den "g" "gb";
        in
        {
          imports = [
            two
            (ex den form b)
          ];
          den.aspects.tux.includes = [
            a
            b
          ];
          expr = {
            ga = has igloo "ga";
            gb = has igloo "gb";
          };
          expected = {
            ga = true;
            gb = false;
          };
        }
      )
    )
    // both "f1d-displaced-exclude-first" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = up den "g" "ga";
          b = up den "g" "gb";
        in
        {
          imports = [
            two
            (ex den form a)
          ];
          den.aspects.tux.includes = [
            a
            b
          ];
          expr = {
            ga = has igloo "ga";
            gb = has igloo "gb";
          };
          expected = {
            ga = false;
            gb = true;
          };
        }
      )
    )
    # F2: an aspect named like the excluded policy record survives.
    // both "f2-aspect-namesake-survives" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = up den "g" "ga";
        in
        {
          imports = [
            two
            (ex den form a)
          ];
          den.aspects.g.nixos.environment.etc.ag.text = "x";
          den.aspects.igloo.includes = [ den.aspects.g ];
          den.aspects.tux.includes = [ a ];
          expr = {
            ga = has igloo "ga";
            ag = has igloo "ag";
          };
          expected = {
            ga = false;
            ag = true;
          };
        }
      )
    )
    # F2r: an aspect exclude leaves a policy that only shares the aspect's name.
    // both "f2r-aspect-exclude-leaves-namesake-policy" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form den.aspects.g)
          ];
          den.aspects.g.nixos.environment.etc.ag.text = "x";
          den.aspects.pingu.includes = [ den.aspects.g ];
          den.aspects.tux.includes = [ (up den "g" "ga") ];
          expr = {
            ga = has igloo "ga";
            ag = has igloo "ag";
          };
          expected = {
            ga = true;
            ag = false;
          };
        }
      )
    )
    # F3: author record "tux/to-hosts" on pingu (not displaced) beside den's cross policy.
    // both "f3-author-record-vs-den-cross" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = up den "tux/to-hosts" "forged";
        in
        {
          imports = [
            two
            (ex den form a)
          ];
          den.schema.host.includes = [ den.batteries.mutual-provider ];
          den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
          den.aspects.pingu.includes = [ a ];
          expr = {
            forged = has igloo "forged";
            real = has igloo "real";
          };
          expected = {
            forged = false;
            real = true;
          };
        }
      )
    )
    // both "f3p-provided-aspect-exclude-vs-sibling-namesake" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = up den "tux/to-hosts" "forged";
        in
        {
          imports = [
            two
            (ex den form den.aspects.tux.provides.to-hosts)
          ];
          den.schema.host.includes = [ den.batteries.mutual-provider ];
          den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
          den.aspects.pingu.includes = [ a ];
          expr = {
            forged = has igloo "forged";
            real = has igloo "real";
          };
          expected = {
            forged = true;
            real = false;
          };
        }
      )
    )
    # F5: two-sided den.default registration, removed on both sides.
    // both "f5-den-default-two-sided" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = up den "dd" "dd";
        in
        {
          imports = [
            two
            (ex den form a)
          ];
          den.default.includes = [ a ];
          expr = has igloo "dd";
          expected = false;
        }
      )
    )
    # F6: #754 class: a { host } policy in an aspect igloo hands its users.
    // both "f6-late-to-users" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = hp den "lt" "lt";
        in
        {
          imports = [
            two
            (ex den form a)
          ];
          den.aspects.carrier.includes = [ a ];
          den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
          den.aspects.igloo.includes = [ den.aspects.dev ];
          expr = has igloo "lt";
          expected = false;
        }
      )
    )
    # F6c control: without the exclude it lands.
    // {
      "test-f6c-late-to-users-control" = denTest (
        { den, igloo, ... }:
        {
          imports = [ two ];
          den.aspects.carrier.includes = [ (hp den "lt" "lt") ];
          den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
          den.aspects.igloo.includes = [ den.aspects.dev ];
          expr = has igloo "lt";
          expected = true;
        }
      );
    }
    # F7: ruling (a): nested in tux.provides.to-hosts.
    // both "f7-provenance-nested" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = hp den "pv" "pv";
        in
        {
          imports = [
            two
            (ex den form a)
          ];
          den.schema.host.includes = [ den.batteries.mutual-provider ];
          den.aspects.tux.provides.to-hosts.includes = [ a ];
          expr = has igloo "pv";
          expected = false;
        }
      )
    )
    # F8: a den.policies record merged by priority.
    // both "f8-module-merged-record" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form den.policies.mm)
            {
              den.policies.mm = lib.mkDefault (
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.mm-default.text = "x";
                  })
                ]
              );
            }
            {
              den.policies.mm =
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.mm.text = "x";
                  })
                ];
            }
          ];
          den.aspects.tux.includes = [ den.policies.mm ];
          expr = {
            mm = has igloo "mm";
            d = has igloo "mm-default";
          };
          expected = {
            mm = false;
            d = false;
          };
        }
      )
    )
    # F8u: den's user-to-host excluded from the host, both forms.
    // both "f8u-user-to-host" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form den.policies.user-to-host)
          ];
          den.aspects.tux.user.description = "tux";
          expr = igloo.users.users.tux.description or "<absent>";
          expected = "<absent>";
        }
      )
    )
    # F9: wrapped records; exclude the inner record.
    // both "f9s-strict-wrapped" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form den.policies.w)
          ];
          den.policies.w =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.w.text = "x";
              })
            ];
          den.aspects.tux.includes = [ (den.lib.policy.strict den.policies.w) ];
          # igloo isn't the strict policy's registrant (tux is): refused, §11a O2.
          expr = has igloo "w";
          expected = true;
        }
      )
    )
    // both "f9w-when-wrapped" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form den.policies.w)
          ];
          den.policies.w =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.w.text = "x";
              })
            ];
          den.aspects.tux.includes = [ (den.lib.policy.when ({ host, ... }: true) den.policies.w) ];
          expr = has igloo "w";
          expected = false;
        }
      )
    )
    // both "f9f-for-wrapped" (
      form:
      denTest (
        {
          den,
          igloo,
          config,
          ...
        }:
        {
          imports = [
            two
            (ex den form den.policies.w)
          ];
          den.policies.w =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.w.text = "x";
              })
            ];
          den.aspects.tux.includes = [
            (den.lib.policy.for config.den.hosts.x86_64-linux.igloo den.policies.w)
          ];
          expr = has igloo "w";
          expected = false;
        }
      )
    )
    # Origin matcher: an inline aspect that only shares an aspect's name.
    // both "o1-inline-namesake-aspect" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form den.aspects.tools)
          ];
          den.aspects.tools.nixos.environment.etc.tools.text = "x";
          den.aspects.pingu.includes = [ den.aspects.tools ];
          den.aspects.tux.includes = [
            {
              name = "tools";
              includes = [ (up den "inl" "inl") ];
            }
          ];
          expr = has igloo "inl";
          expected = true;
        }
      )
    )
    # Origin matcher: a parametric aspect's policy.
    // both "o2-parametric-aspect-origin" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form den.aspects.role)
          ];
          den.aspects.role =
            { host, ... }:
            {
              includes = [ (up den "rp" "rp") ];
            };
          den.aspects.tux.includes = [ den.aspects.role ];
          expr = has igloo "rp";
          expected = false;
        }
      )
    );
}
