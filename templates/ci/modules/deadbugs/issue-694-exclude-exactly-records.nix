# #694 round 4: excludes of parametric and wrapped records, both forms.
{ denTest, lib, ... }:
let
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
  exL = on: x: { den.aspects.${on}.excludes = [ x ]; };
  exE = den: on: x: {
    den.aspects.${on}.includes = [
      (den.lib.policy.mkPolicy "do-exclude" ({ host, ... }: [ (den.lib.policy.exclude x) ]))
    ];
  };
  ex =
    den: form: on: x:
    if form == "L" then exL on x else exE den on x;
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
  # A parametric constructor: one call per use.
  mkP = den: x: up den "pp(${x})" "pp-${x}";
  # The finished pipeline state for igloo, read by the unmatched diagnostic.
  stateOf =
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
  flake.tests.deadbugs.issue-694-exclude-exactly-records =
    # P1: parametric record, a second call with the same argument; other argument survives.
    both "p1-parametric-record" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form "igloo" (mkP den "a"))
          ];
          den.aspects.tux.includes = [ (mkP den "a") ];
          den.aspects.pingu.includes = [ (mkP den "b") ];
          # A constructor builds a new record on each call, so a second call
          # names nothing that registered (disclosed limit): a still lands.
          expr = {
            a = has igloo "pp-a";
            b = has igloo "pp-b";
          };
          expected = {
            a = true;
            b = true;
          };
        }
      )
    )
    # P1s: the same, the excluded value shared (one let binding).
    // both "p1s-parametric-record-shared-value" (
      form:
      denTest (
        { den, igloo, ... }:
        let
          a = mkP den "a";
        in
        {
          imports = [
            two
            (ex den form "igloo" a)
          ];
          den.aspects.tux.includes = [ a ];
          den.aspects.pingu.includes = [ (mkP den "b") ];
          expr = {
            a = has igloo "pp-a";
            b = has igloo "pp-b";
          };
          expected = {
            a = false;
            b = true;
          };
        }
      )
    )
    # S1: policy.strict, excluded by its registrant tux.
    // both "s1-strict-by-registrant" (
      form:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (ex den form "tux" den.policies.w)
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
          expr = has igloo "w";
          expected = false;
        }
      )
    )
    # LE: the same record excluded both ways at once; a namesake on pingu survives.
    // {
      "test-le-both-forms-together" = denTest (
        { den, igloo, ... }:
        let
          a = up den "g" "ga";
          b = up den "g" "gb";
        in
        {
          imports = [
            two
            (exL "igloo" a)
            (exE den "igloo" a)
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
      );
    }
    # The unmatched-exclude warning: with a namesake registered, it adds the
    # hint for a constructor; without one, it is the plain warning. The name
    # only picks the text.
    // {
      "test-p1-unmatched-warning-hints-at-constructor" = denTest (
        { den, ... }:
        {
          imports = [
            two
            (exL "igloo" (mkP den "a"))
          ];
          den.aspects.tux.includes = [ (mkP den "a") ];
          expr = builtins.any (
            m: builtins.match ".*did register: if it is built by a constructor.*" m != null
          ) (den.lib.aspects.fx.handlers.unmatchedRawRefExcludes (stateOf den));
          expected = true;
        }
      );
      "test-unmatched-warning-plain-without-namesake" = denTest (
        { den, ... }:
        {
          imports = [
            two
            (exL "igloo" (mkP den "a"))
          ];
          expr = map (m: builtins.match ".*did register.*" m != null) (
            den.lib.aspects.fx.handlers.unmatchedRawRefExcludes (stateOf den)
          );
          expected = [ false ];
        }
      );
      # An author's own record claiming to wrap one is its own record: an
      # exclude of the record it names leaves it ("no more").
      "test-author-wraps-field-not-reached-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "igloo" den.policies.w)
          ];
          den.policies.w = { host, user, ... }: [ ];
          den.aspects.tux.includes = [
            ((up den "w" "aw") // { __wraps = den.policies.w; })
          ];
          expr = has igloo "aw";
          expected = true;
        }
      );
      "test-author-wraps-field-not-reached-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "igloo" den.policies.w)
          ];
          den.policies.w = { host, user, ... }: [ ];
          den.aspects.tux.includes = [
            ((up den "w" "aw") // { __wraps = den.policies.w; })
          ];
          expr = has igloo "aw";
          expected = true;
        }
      );
      # A den combinator's record with its `fn` replaced by `//` keeps
      # `__wraps`, but it is no longer den's: an exclude of the wrapped record
      # leaves it. The real wrapped record is still removed.
      "test-w2-replaced-fn-not-reached-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "tux" den.policies.w)
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
            (
              (den.lib.policy.strict den.policies.w)
              // {
                fn =
                  { host, user, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "nixos";
                      receiver = host;
                      module.environment.etc.other.text = "x";
                    })
                  ];
              }
            )
            (
              (den.lib.policy.when ({ host, ... }: true) den.policies.w)
              // {
                fn =
                  { host, user, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "nixos";
                      receiver = host;
                      module.environment.etc.other2.text = "x";
                    })
                  ];
              }
            )
          ];
          expr = {
            other = has igloo "other";
            other2 = has igloo "other2";
          };
          expected = {
            other = true;
            other2 = true;
          };
        }
      );
      "test-w2-replaced-fn-not-reached-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "tux" den.policies.w)
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
            (
              (den.lib.policy.strict den.policies.w)
              // {
                fn =
                  { host, user, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "nixos";
                      receiver = host;
                      module.environment.etc.other.text = "x";
                    })
                  ];
              }
            )
            (
              (den.lib.policy.when ({ host, ... }: true) den.policies.w)
              // {
                fn =
                  { host, user, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "nixos";
                      receiver = host;
                      module.environment.etc.other2.text = "x";
                    })
                  ];
              }
            )
          ];
          expr = {
            other = has igloo "other";
            other2 = has igloo "other2";
          };
          expected = {
            other = true;
            other2 = true;
          };
        }
      );
      # strict wrapping strict, excluded by its registrant: removed.
      "test-w4-strict-strict-by-registrant-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "tux" den.policies.w)
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
          den.aspects.tux.includes = [ (den.lib.policy.strict (den.lib.policy.strict den.policies.w)) ];
          expr = has igloo "w";
          expected = false;
        }
      );
      "test-w4-strict-strict-by-registrant-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "tux" den.policies.w)
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
          den.aspects.tux.includes = [ (den.lib.policy.strict (den.lib.policy.strict den.policies.w)) ];
          expr = has igloo "w";
          expected = false;
        }
      );
      # D-C2: a den combinator registered under its own name in den.policies
      # is reached by an exclude of the record it wraps (name is identity, and
      # den also files it under the wrapped record's name).
      "test-dc2-registered-strict-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "tux" den.policies.w)
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
          den.policies.sw = den.lib.policy.strict den.policies.w;
          den.aspects.tux.includes = [ den.policies.sw ];
          expr = has igloo "w";
          expected = false;
        }
      );
      "test-dc2-registered-when-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "igloo" den.policies.w)
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
          den.policies.ww = den.lib.policy.when ({ host, ... }: true) den.policies.w;
          den.aspects.tux.includes = [ den.policies.ww ];
          expr = has igloo "w";
          expected = false;
        }
      );
      "test-dc2-registered-strict-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "tux" den.policies.w)
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
          den.policies.sw = den.lib.policy.strict den.policies.w;
          den.aspects.tux.includes = [ den.policies.sw ];
          expr = has igloo "w";
          expected = false;
        }
      );
      "test-dc2-registered-when-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "igloo" den.policies.w)
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
          den.policies.ww = den.lib.policy.when ({ host, ... }: true) den.policies.w;
          den.aspects.tux.includes = [ den.policies.ww ];
          expr = has igloo "w";
          expected = false;
        }
      );
      # The other direction: an author's renamed copy carrying its own
      # `__wraps` isn't den's combinator, and a namesake record isn't moved.
      "test-dc2-author-wraps-renamed-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "igloo" den.policies.w)
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
          den.policies.aw = {
            __isPolicy = true;
            name = "aw";
            __wraps = den.policies.w;
            fn =
              { host, user, ... }:
              [
                (den.lib.policy.provide {
                  class = "nixos";
                  receiver = host;
                  module.environment.etc.aw.text = "x";
                })
              ];
          };
          den.aspects.tux.includes = [ den.policies.aw ];
          expr = has igloo "aw";
          expected = true;
        }
      );
      "test-dc2-author-wraps-renamed-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "igloo" den.policies.w)
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
          den.policies.aw = {
            __isPolicy = true;
            name = "aw";
            __wraps = den.policies.w;
            fn =
              { host, user, ... }:
              [
                (den.lib.policy.provide {
                  class = "nixos";
                  receiver = host;
                  module.environment.etc.aw.text = "x";
                })
              ];
          };
          den.aspects.tux.includes = [ den.policies.aw ];
          expr = has igloo "aw";
          expected = true;
        }
      );
      # An author's rename of den's combinator is a change, not den's rename.
      "test-dc2-author-renamed-strict-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "tux" den.policies.w)
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
          den.aspects.tux.includes = [ ((den.lib.policy.strict den.policies.w) // { name = "x"; }) ];
          expr = has igloo "w";
          expected = true;
        }
      );
      # An author's rename of den's combinator is a change, not den's rename.
      "test-dc2-author-renamed-strict-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "tux" den.policies.w)
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
          den.aspects.tux.includes = [ ((den.lib.policy.strict den.policies.w) // { name = "x"; }) ];
          expr = has igloo "w";
          expected = true;
        }
      );
      "test-dc2-namesake-not-displaced" = denTest (
        { den, config, ... }:
        let
          st =
            (den.lib.aspects.resolveWithState "nixos" (
              den.lib.resolveEntity "host" { host = config.den.hosts.x86_64-linux.igloo; }
            )).state;
          keys = lib.concatMap builtins.attrNames (
            builtins.attrValues ((st.scopedAspectPolicies or (_: { })) null)
          );
        in
        {
          imports = [ two ];
          den.policies.w = { host, user, ... }: [ ];
          den.policies.sw = den.lib.policy.strict den.policies.w;
          den.aspects.tux.includes = [
            den.policies.sw
            den.policies.w
          ];
          expr = builtins.filter (k: builtins.match "(.*/)?w(#[0-9]+)?" k != null) keys;
          expected = [ "w" ];
        }
      );
      # A combinator's halves can't be grafted: `when A` given `when w`'s
      # wrapped record, or its whole bundle, is still `when A`, and an exclude
      # of `w` leaves it.
      "test-r4-wraps-graft-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "igloo" den.policies.w)
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
          den.policies.a =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.a.text = "x";
              })
            ];
          den.aspects.tux.includes = [
            (
              (den.lib.policy.when ({ host, ... }: true) den.policies.a)
              // builtins.intersectAttrs { __wraps = null; } (
                den.lib.policy.when ({ host, ... }: true) den.policies.w
              )
            )
          ];
          expr = has igloo "a";
          expected = true;
        }
      );
      "test-r4-bundle-graft-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "igloo" den.policies.w)
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
          den.policies.a =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.a.text = "x";
              })
            ];
          den.aspects.tux.includes = [
            (
              (den.lib.policy.when ({ host, ... }: true) den.policies.a)
              // builtins.intersectAttrs {
                __wraps = null;
                __denWrap = null;
              } (den.lib.policy.when ({ host, ... }: true) den.policies.w)
            )
          ];
          expr = has igloo "a";
          expected = true;
        }
      );
      "test-r4-wraps-graft-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "igloo" den.policies.w)
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
          den.policies.a =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.a.text = "x";
              })
            ];
          den.aspects.tux.includes = [
            (
              (den.lib.policy.when ({ host, ... }: true) den.policies.a)
              // builtins.intersectAttrs { __wraps = null; } (
                den.lib.policy.when ({ host, ... }: true) den.policies.w
              )
            )
          ];
          expr = has igloo "a";
          expected = true;
        }
      );
      "test-r4-bundle-graft-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "igloo" den.policies.w)
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
          den.policies.a =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.a.text = "x";
              })
            ];
          den.aspects.tux.includes = [
            (
              (den.lib.policy.when ({ host, ... }: true) den.policies.a)
              // builtins.intersectAttrs {
                __wraps = null;
                __denWrap = null;
              } (den.lib.policy.when ({ host, ... }: true) den.policies.w)
            )
          ];
          expr = has igloo "a";
          expected = true;
        }
      );
      # policy.strict excluded by igloo, not its registrant: refused in both
      # forms (§11a O2), as excluded by tux it is removed in both (s1).
      "test-s1i-strict-by-non-registrant-L" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exL "igloo" den.policies.w)
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
          expr = has igloo "w";
          expected = true;
        }
      );
      "test-s1i-strict-by-non-registrant-E" = denTest (
        { den, igloo, ... }:
        {
          imports = [
            two
            (exE den "igloo" den.policies.w)
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
          expr = has igloo "w";
          expected = true;
        }
      );
    };
}
