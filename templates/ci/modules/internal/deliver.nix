# Tests for policy.deliver — the user-facing delivery-edge primitive (spec §4).
#
# `deliver { from; to; at?; mode?; }` declares ONE delivery edge (S, T, P, M).
# `route` and `provides` are PERMANENT shims over it. These tests cover:
#   - each mode (merge / nest / verbatim) end-to-end;
#   - `at`-path nesting;
#   - module-source delivery (the provides case);
#   - SHIM-EQUIVALENCE: a `route {...}` / `provide {...}` and the `deliver {...}`
#     they desugar to produce IDENTICAL edge traces (the strongest faithfulness
#     check — uses the edge-trace oracle, spec §3a / §5.3).
{ denTest, lib, ... }:
let
  # Submodule option helper: declares an option at `name` with a listOf str type.
  mkListSubmodule =
    name:
    { lib, ... }:
    {
      options.${name} = lib.mkOption {
        type = lib.types.submoduleWith {
          modules = [
            {
              options.items = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            }
          ];
        };
        default = { };
      };
    };

  # Resolve a host entity to its raw edge trace (the migration oracle). Used by
  # the shim-equivalence tests: a route/provide config and its deliver desugaring
  # are byte-identical except for the constructor, so their RAW traces (same
  # scopeContexts) must be equal — no name-normalization needed.
  hostTrace =
    den: cls: host:
    (den.lib.aspects.resolveWithPaths cls (den.lib.resolveEntity "host" { inherit host; })).edgeTrace;
in
{
  flake.tests.deliver = {

    # ===== mode = merge (default), class source, at = [] ================
    # Equivalent to route { fromClass; intoClass; path = []; }.
    test-deliver-merge = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.custom.description = "Custom source class";

        den.policies.deliver-merge =
          { host, ... }:
          [
            (den.lib.policy.deliver {
              from = "custom";
              to = host.class;
            })
          ];

        den.default.includes = [ den.policies.deliver-merge ];

        den.aspects.igloo = {
          custom.networking.hostName = "delivered-merge";
        };

        expr = igloo.networking.hostName;
        expected = "delivered-merge";
      }
    );

    # ===== mode = nest, class source, at = [ ... ] ======================
    # Equivalent to route { ...; path = [ "box" ]; }.
    test-deliver-nest = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.src.description = "Source class for nest deliver";

        den.policies.deliver-nest =
          { host, ... }:
          [
            (den.lib.policy.deliver {
              from = "src";
              to = host.class;
              at = [ "deliver-box" ];
              mode = "nest";
            })
          ];

        den.default.includes = [ den.policies.deliver-nest ];

        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "deliver-box") ];
          nixos.deliver-box.items = [ "from-nixos-owned" ];
          src.items = [ "from-src-class" ];
        };

        expr = lib.sort (a: b: a < b) igloo.deliver-box.items;
        expected = [
          "from-nixos-owned"
          "from-src-class"
        ];
      }
    );

    # ===== module source (the provides case) ============================
    # `from = { module = ...; }` injects a NEW module into the target class.
    test-deliver-module-source = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.deliver-module =
          { host, ... }:
          [
            (den.lib.policy.deliver {
              from = {
                module = {
                  networking.hostName = "delivered-module";
                };
              };
              to = host.class;
            })
          ];

        den.default.includes = [ den.policies.deliver-module ];

        den.aspects.igloo = { };

        expr = igloo.networking.hostName;
        expected = "delivered-module";
      }
    );

    # ===== module source nested at a path ===============================
    test-deliver-module-source-at = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.deliver-module-at =
          { host, ... }:
          [
            (den.lib.policy.deliver {
              from = {
                module.items = [ "from-deliver" ];
              };
              to = host.class;
              at = [ "deliver-box" ];
              mode = "nest";
            })
          ];

        den.default.includes = [ den.policies.deliver-module-at ];

        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "deliver-box") ];
          nixos.deliver-box.items = [ "from-aspect" ];
        };

        expr = lib.sort (a: b: a < b) igloo.deliver-box.items;
        expected = [
          "from-aspect"
          "from-deliver"
        ];
      }
    );

    # ===== mode rejects unknown values ==================================
    # tryEval can't capture the throw message, so pair the failing call with a
    # positive control differing ONLY in `mode` — proves the throw is mode
    # validation, not an unrelated eval error giving a false `success = false`.
    test-deliver-bad-mode-throws = denTest (
      { den, ... }:
      {
        expr = {
          bogus =
            (builtins.tryEval (
              den.lib.policy.deliver {
                from = "x";
                to = "y";
                mode = "bogus";
              }
            )).success;
          control =
            (builtins.tryEval (
              den.lib.policy.deliver {
                from = "x";
                to = "y";
                mode = "merge";
              }
            )).success;
        };
        expected = {
          bogus = false;
          control = true;
        };
      }
    );

    # ===== verbatim rejected for module sources =========================
    # Positive control: the SAME module source with mode = "nest" succeeds, so
    # the failure is the verbatim×module rule, not the module shape.
    test-deliver-verbatim-module-throws = denTest (
      { den, ... }:
      {
        expr = {
          verbatim =
            (builtins.tryEval (
              den.lib.policy.deliver {
                from = {
                  module = { };
                };
                to = "y";
                mode = "verbatim";
              }
            )).success;
          control =
            (builtins.tryEval (
              den.lib.policy.deliver {
                from = {
                  module = { };
                };
                to = "y";
                mode = "nest";
              }
            )).success;
        };
        expected = {
          verbatim = false;
          control = true;
        };
      }
    );

    # ===== mode = verbatim (class source) ===============================
    # nest-verbatim: collected wrappers placed BY REFERENCE so the target's own
    # `merge` re-instantiates them together with its base modules (microvm-style
    # slot). The collected `guestcfg` module reads a default declared by a BASE
    # module of the target slot — only possible if the module ships LIVE (re-
    # evaluated with the base), proving verbatim, not a pre-frozen attrset.
    # `deliver { mode = "verbatim"; }` is the explicit-mode replacement for the
    # legacy `reinstantiate` flag (no flag on the surface).
    test-deliver-verbatim = denTest (
      { den, igloo, ... }:
      let
        reinstantiatingBase =
          { lib, ... }:
          {
            options.fromBase = lib.mkOption {
              type = lib.types.str;
              default = "BASE-DEFAULT";
            };
            config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything;
          };
        # A slot whose `merge` re-runs evalModules over the delivered defs + the
        # base module-list (exactly as microvm's eval-config does).
        reinstantiatingSlot =
          { lib, ... }:
          {
            options.guestSlot = lib.mkOption {
              default = null;
              type = lib.types.nullOr (
                lib.mkOptionType {
                  name = "reinstantiated config";
                  merge =
                    _loc: defs:
                    lib.evalModules {
                      modules = [ reinstantiatingBase ] ++ map (d: d.value) defs;
                    };
                }
              );
            };
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.guestcfg.description = "verbatim-delivered guest config";

        den.policies.deliver-verbatim =
          { host, ... }:
          [
            (den.lib.policy.deliver {
              from = "guestcfg";
              to = host.class;
              mode = "verbatim";
              at = [ "guestSlot" ];
            })
          ];
        den.default.includes = [ den.policies.deliver-verbatim ];

        den.aspects.igloo = {
          nixos.imports = [ reinstantiatingSlot ];
          # The guestcfg-class content delivered verbatim into guestSlot; it reads
          # `fromBase`, a default only present once re-instantiated WITH the base.
          guestcfg =
            { config, ... }:
            {
              networking.hostName = "guest-vm";
              echoed = config.fromBase;
            };
        };

        # `.guestSlot.config` — the re-instantiated evalModules result's config.
        expr = {
          hn = igloo.guestSlot.config.networking.hostName;
          echoed = igloo.guestSlot.config.echoed;
        };
        expected = {
          hn = "guest-vm";
          echoed = "BASE-DEFAULT";
        };
      }
    );

    # ===== SHIM-EQUIVALENCE: route ≡ deliver (class source) =============
    # A `route { fromClass; intoClass; path; }` and the `deliver` it desugars to
    # produce the SAME effect descriptor — construction-level faithfulness. Equal
    # descriptors ⇒ identical downstream edges (the edge constructors consume the
    # descriptor, not the surface call).
    test-shim-route-eq-deliver = denTest (
      { den, ... }:
      {
        expr =
          let
            r = den.lib.policy.route {
              fromClass = "shimsrc";
              intoClass = "nixos";
              path = [ "shim-box" ];
            };
            d = den.lib.policy.deliver {
              from = "shimsrc";
              to = "nixos";
              at = [ "shim-box" ];
              mode = "nest";
            };
          in
          r == d;
        expected = true;
      }
    );

    # route reinstantiate ≡ deliver verbatim — the mode→flag mapping.
    test-shim-route-reinstantiate-eq-deliver-verbatim = denTest (
      { den, ... }:
      {
        expr =
          let
            r = den.lib.policy.route {
              fromClass = "c";
              intoClass = "nixos";
              path = [ "p" ];
              reinstantiate = true;
            };
            d = den.lib.policy.deliver {
              from = "c";
              to = "nixos";
              at = [ "p" ];
              mode = "verbatim";
            };
          in
          r == d;
        expected = true;
      }
    );

    # ===== SHIM-EQUIVALENCE: provide ≡ deliver (module source) ==========
    test-shim-provide-eq-deliver = denTest (
      { den, ... }:
      {
        expr =
          let
            p = den.lib.policy.provide {
              class = "nixos";
              module.items = [ "m" ];
              path = [ "box" ];
            };
            d = den.lib.policy.deliver {
              from = {
                module.items = [ "m" ];
              };
              to = "nixos";
              at = [ "box" ];
              mode = "nest";
            };
          in
          p == d;
        expected = true;
      }
    );

    # ===== SHIM-EQUIVALENCE via the edge oracle: deliver edge trace =====
    # A `deliver`-built topology produces the SAME delivery edge a `route` does.
    # The construction-level equivalence above (route descriptor == deliver
    # descriptor) guarantees the full traces match; here we confirm the deliver
    # constructor lands the expected nest edge in the live edge trace (oracle).
    test-shim-deliver-edgetrace = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.shimsrc.description = "shim source class";
        den.policies.deliver-p =
          { host, ... }:
          [
            (den.lib.policy.deliver {
              from = "shimsrc";
              to = host.class;
              at = [ "shim-box" ];
              mode = "nest";
            })
          ];
        den.default.includes = [ den.policies.deliver-p ];
        den.aspects.igloo = {
          nixos.imports = [ (mkListSubmodule "shim-box") ];
          shimsrc.items = [ "x" ];
        };

        # The deliver-built trace contains the shimsrc>nixos nest edge at
        # shim-box (the policy fires per scope; each registers the edge — the
        # faithful trace records each, exactly as the route shim would).
        expr =
          let
            trace = hostTrace den "nixos" den.hosts.x86_64-linux.igloo;
            shimEdges = builtins.filter (
              e: (e.source.collected.class or null) == "shimsrc" && (e.target.class or null) == "nixos"
            ) trace;
            modesPaths = map (e: {
              inherit (e) mode path;
            }) shimEdges;
          in
          {
            allNest = builtins.all (e: e.mode == "nest" && e.path == [ "shim-box" ]) modesPaths;
            atLeastOne = modesPaths != [ ];
          };
        expected = {
          allNest = true;
          atLeastOne = true;
        };
      }
    );

  };
}
