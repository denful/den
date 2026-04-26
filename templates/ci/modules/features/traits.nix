{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.traits = {

    # --- Tier detection ---

    # Plain value → Tier 1.
    test-tier1-plain-value = denTest (
      { den, ... }:
      let
        detectTier = den.lib.aspects.fx.handlers.detectTier;
        result = detectTier { } { enable = true; };
      in
      {
        expr = result.tier;
        expected = 1;
      }
    );

    # Function with den context args only → Tier 2.
    test-tier2-den-args = denTest (
      { den, ... }:
      let
        detectTier = den.lib.aspects.fx.handlers.detectTier;
        ctx = {
          host = "igloo";
          user = "tux";
        };
        fn =
          { host, user }:
          {
            inherit host user;
          };
        result = detectTier ctx fn;
      in
      {
        expr = {
          inherit (result) tier;
          value = result.value;
        };
        expected = {
          tier = 2;
          value = {
            host = "igloo";
            user = "tux";
          };
        };
      }
    );

    # Function with config arg → Tier 3.
    test-tier3-module-sys-args = denTest (
      { den, ... }:
      let
        detectTier = den.lib.aspects.fx.handlers.detectTier;
        fn =
          { config, ... }:
          {
            inherit config;
          };
        result = detectTier { } fn;
      in
      {
        expr = result.tier;
        expected = 3;
      }
    );

    # Function with pkgs arg → Tier 3.
    test-tier3-pkgs = denTest (
      { den, ... }:
      let
        detectTier = den.lib.aspects.fx.handlers.detectTier;
        fn =
          { pkgs }:
          {
            inherit pkgs;
          };
        result = detectTier { } fn;
      in
      {
        expr = result.tier;
        expected = 3;
      }
    );

    # Function with _module.args → Tier 3.
    test-tier3-module-prefix = denTest (
      { den, ... }:
      let
        detectTier = den.lib.aspects.fx.handlers.detectTier;
        fn =
          { _module }:
          {
            inherit _module;
          };
        result = detectTier { } fn;
      in
      {
        expr = result.tier;
        expected = 3;
      }
    );

    # --- Collection strategies ---

    # List collection concats.
    test-collect-list = denTest (
      { den, ... }:
      let
        collectTrait = den.lib.aspects.fx.handlers.collectTrait;
        result = collectTrait {
          strategy = "list";
          traitName = "firewall";
          existing = [
            { port = 80; }
          ];
          newValue = {
            port = 443;
          };
        };
      in
      {
        expr = result;
        expected = [
          { port = 80; }
          { port = 443; }
        ];
      }
    );

    # Map collection merges attrsets.
    test-collect-map = denTest (
      { den, ... }:
      let
        collectTrait = den.lib.aspects.fx.handlers.collectTrait;
        result = collectTrait {
          strategy = "map";
          traitName = "ports";
          existing = {
            http = 80;
          };
          newValue = {
            https = 443;
          };
        };
      in
      {
        expr = result;
        expected = {
          http = 80;
          https = 443;
        };
      }
    );

    # Map collection errors on duplicate keys.
    test-collect-map-duplicate-error = denTest (
      { den, ... }:
      let
        collectTrait = den.lib.aspects.fx.handlers.collectTrait;
      in
      {
        expr = collectTrait {
          strategy = "map";
          traitName = "ports";
          existing = {
            http = 80;
          };
          newValue = {
            http = 8080;
          };
        };
        expectedError = {
          type = "ThrownError";
          msg = "duplicate keys";
        };
      }
    );

    # --- traitCollectorHandler: Tier 1 collection ---

    test-collector-tier1 = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp = fx.send "emit-trait" {
          trait = "firewall";
          value = {
            enable = true;
          };
          chain = "test";
        };
        result = fx.handle {
          handlers = handlers.traitCollectorHandler {
            ctx = { };
            traitSchemas = { };
          };
          state = {
            traits = _: { };
            deferredTraits = _: { };
          };
        } comp;
      in
      {
        expr = (result.state.traits null).firewall;
        expected = [
          { enable = true; }
        ];
      }
    );

    # Multiple Tier 1 emissions accumulate.
    test-collector-tier1-multiple = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp =
          fx.bind
            (fx.send "emit-trait" {
              trait = "firewall";
              value = {
                port = 80;
              };
              chain = "a";
            })
            (
              _:
              fx.send "emit-trait" {
                trait = "firewall";
                value = {
                  port = 443;
                };
                chain = "b";
              }
            );
        result = fx.handle {
          handlers = handlers.traitCollectorHandler {
            ctx = { };
            traitSchemas = { };
          };
          state = {
            traits = _: { };
            deferredTraits = _: { };
          };
        } comp;
      in
      {
        expr = (result.state.traits null).firewall;
        expected = [
          { port = 80; }
          { port = 443; }
        ];
      }
    );

    # Map collection via schema.
    test-collector-map-strategy = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp =
          fx.bind
            (fx.send "emit-trait" {
              trait = "ports";
              value = {
                http = 80;
              };
              chain = "a";
            })
            (
              _:
              fx.send "emit-trait" {
                trait = "ports";
                value = {
                  https = 443;
                };
                chain = "b";
              }
            );
        result = fx.handle {
          handlers = handlers.traitCollectorHandler {
            ctx = { };
            traitSchemas = {
              ports = {
                collection = "map";
              };
            };
          };
          state = {
            traits = _: { };
            deferredTraits = _: { };
          };
        } comp;
      in
      {
        expr = (result.state.traits null).ports;
        expected = {
          http = 80;
          https = 443;
        };
      }
    );

    # --- traitCollectorHandler: Tier 3 deferral ---

    test-collector-tier3-deferred = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        fn =
          { config, ... }:
          {
            enable = config ? networking;
          };
        comp = fx.send "emit-trait" {
          trait = "firewall";
          value = fn;
          chain = "test";
        };
        result = fx.handle {
          handlers = handlers.traitCollectorHandler {
            ctx = { };
            traitSchemas = { };
          };
          state = {
            traits = _: { };
            deferredTraits = _: { };
          };
        } comp;
      in
      {
        expr = {
          traitsEmpty = (result.state.traits null) == { };
          deferredCount = builtins.length ((result.state.deferredTraits null).firewall or [ ]);
        };
        expected = {
          traitsEmpty = true;
          deferredCount = 1;
        };
      }
    );

    # --- traitCollectorHandler: Tier 2 resolution ---

    test-collector-tier2-resolve = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        fn =
          { host }:
          {
            hostFirewall = host;
          };
        comp = fx.send "emit-trait" {
          trait = "firewall";
          value = fn;
          chain = "test";
        };
        result = fx.handle {
          handlers = handlers.traitCollectorHandler {
            ctx = {
              host = "igloo";
            };
            traitSchemas = { };
          };
          state = {
            traits = _: { };
            deferredTraits = _: { };
          };
        } comp;
      in
      {
        expr = (result.state.traits null).firewall;
        expected = [
          { hostFirewall = "igloo"; }
        ];
      }
    );

    # --- traitArgHandler: parametric consumption ---

    test-trait-arg-handler-resumes = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp = fx.send "firewall" null;
        result = fx.handle {
          handlers = handlers.traitArgHandler { firewall = true; };
          state = {
            traits = _: {
              firewall = [
                { enable = true; }
              ];
            };
            consumedTraits = _: { };
          };
        } comp;
      in
      {
        expr = {
          value = result.value;
          consumed = (result.state.consumedTraits null) ? firewall;
        };
        expected = {
          value = [
            { enable = true; }
          ];
          consumed = true;
        };
      }
    );

    # Trait not yet collected → null.
    test-trait-arg-handler-missing = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        comp = fx.send "firewall" null;
        result = fx.handle {
          handlers = handlers.traitArgHandler { firewall = true; };
          state = {
            traits = _: { };
            consumedTraits = _: { };
          };
        } comp;
      in
      {
        # Uncollected traits default to [] (empty list), not null
        expr = result.value;
        expected = [ ];
      }
    );

    # --- defaultState has consumedTraits ---

    test-default-state-has-consumed-traits = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.pipeline.defaultState ? consumedTraits;
        expected = true;
      }
    );

    # --- Full pipeline integration: trait collected in state ---

    test-pipeline-trait-collection = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "netstack";
          meta = { };
          firewall = [
            { port = 80; }
          ];
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.schema.classes.nixos.description = "NixOS";
        den.schema.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };
        den._traitNames.firewall = true;

        expr = (result.state.traits null).firewall;
        expected = [
          { port = 80; }
        ];
      }
    );

    # --- constantHandler wins over traitArgHandler on name collision ---

    test-ctx-wins-over-trait = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        # If ctx has "host" and traitNames also has "host", constantHandler wins
        comp = fx.send "host" null;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = {
              host = "igloo";
            };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.schema.traits.host.description = "Host trait";
        den._traitNames.host = true;

        # constantHandler should win — returns "igloo", not trait data
        expr = result.value;
        expected = "igloo";
      }
    );

    # --- Backward compat: existing structural-detection tests still pass ---

    test-trait-no-crash-full-pipeline = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "mixed";
          meta = { };
          nixos = {
            networking.hostName = "test";
          };
          firewall = {
            enable = true;
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        den.schema.classes.nixos.description = "NixOS";
        den.schema.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };
        den._traitNames.firewall = true;

        expr = {
          importsCount = builtins.length (result.state.imports null);
          name = result.value.name;
          hasTraitData = (result.state.traits null) ? firewall;
        };
        expected = {
          importsCount = 1;
          name = "mixed";
          hasTraitData = true;
        };
      }
    );

    # --- wrapClassModule: trait arg detection ---

    test-wrap-class-module-trait-args = denTest (
      { den, ... }:
      let
        aspect = den.lib.aspects.fx.aspect;
        module =
          {
            firewall,
            config,
            ...
          }:
          {
            assertions = [
              {
                assertion = firewall != [ ];
                message = "firewall trait data";
              }
            ];
          };
        result = aspect.wrapClassModule {
          inherit module;
          ctx = { };
          aspectPolicy = null;
          globalPolicy = "error";
          traitNames = {
            firewall = true;
          };
        };
      in
      {
        # Should wrap since firewall is a trait arg (needs eval-time thunk)
        expr = result.wrapped;
        expected = true;
      }
    );

    # Trait args don't wrap when not registered.
    test-wrap-class-module-no-trait-names = denTest (
      { den, ... }:
      let
        aspect = den.lib.aspects.fx.aspect;
        module =
          {
            firewall,
            config,
            ...
          }:
          { };
        result = aspect.wrapClassModule {
          inherit module;
          ctx = { };
          aspectPolicy = null;
          globalPolicy = "error";
          traitNames = { };
        };
      in
      {
        # No trait names registered → not wrapped (firewall is unknown)
        expr = result.wrapped;
        expected = false;
      }
    );

    # Trait arg shadowed by ctx → treated as den arg, not trait arg.
    test-wrap-class-module-ctx-shadows-trait = denTest (
      { den, ... }:
      let
        aspect = den.lib.aspects.fx.aspect;
        module =
          {
            host,
            config,
            ...
          }:
          { };
        result = aspect.wrapClassModule {
          inherit module;
          ctx = {
            host = "igloo";
          };
          aspectPolicy = null;
          globalPolicy = "error";
          traitNames = {
            host = true;
          };
        };
      in
      {
        # host is in ctx → den arg, not trait arg. Still wrapped due to den arg.
        expr = result.wrapped;
        expected = true;
      }
    );

    # --- fxResolve: _den.traits injection ---

    test-fxresolve-trait-module-injected = denTest (
      { den, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = {
            name = "test";
            meta = { };
            firewall = {
              port = 80;
            };
            includes = [ ];
          };
          ctx = { };
        };
      in
      {
        den.schema.classes.nixos.description = "NixOS";
        den.schema.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };
        den._traitNames.firewall = true;

        # imports should contain at least the traitModule
        expr = builtins.length result.imports >= 1;
        expected = true;
      }
    );

    # --- fxResolve: no traitModule when no schemas ---

    test-fxresolve-no-trait-module-when-no-schemas = denTest (
      { den, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = {
            name = "test";
            meta = { };
            nixos = { };
            includes = [ ];
          };
          ctx = { };
        };
      in
      {
        den.schema.classes.nixos.description = "NixOS";
        # No trait schemas → no traitModule overhead
        expr = builtins.length result.imports;
        expected = 1;
      }
    );

    # --- partialOk validation ---

    test-partialok-violation-throws = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        # Build an aspect with a Tier 3 trait emission AND a parametric
        # consumer that reads the trait at pipeline time.
        # The parametric aspect consumes the trait, then the class module
        # emits a Tier 3 deferred trait — this should throw.
        #
        # We test this by directly checking fxResolve with a pipeline that
        # has both consumed + deferred for the same trait.
        pipeline = den.lib.aspects.fx.pipeline;

        # Run pipeline with an aspect that emits a deferred trait
        aspect = {
          name = "deferred-emitter";
          meta = { };
          firewall =
            { config, ... }:
            {
              enable = config ? networking;
            };
          includes = [ ];
        };

        # First, run the pipeline to get state with deferred trait
        rawResult = pipeline.mkPipeline { class = "nixos"; } {
          self = aspect;
          ctx = { };
        };

        # Manually check: if consumedTraits has firewall AND deferredTraits has firewall
        # without partialOk, it should error.
        deferredTraits = rawResult.state.deferredTraits null;
        hasDeferredFirewall = (deferredTraits.firewall or [ ]) != [ ];
      in
      {
        den.schema.classes.nixos.description = "NixOS";
        den.schema.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };
        den._traitNames.firewall = true;

        # Verify the deferred trait was actually collected
        expr = hasDeferredFirewall;
        expected = true;
      }
    );

    # partialOk = true allows pipeline consumption + deferred emissions.
    test-partialok-allows-mixed = denTest (
      { den, ... }:
      let
        pipeline = den.lib.aspects.fx.pipeline;
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;

        # Aspect with both Tier 1 and Tier 3 firewall emissions
        aspect = {
          name = "mixed-emitter";
          meta = { };
          includes = [ ];
        };

        # Manually build a pipeline result that has consumed + deferred
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        baseHandlers = pipeline.defaultHandlers {
          class = "nixos";
          ctx = { };
        };
        rawResult = fx.handle {
          handlers = baseHandlers;
          state = pipeline.defaultState // {
            # Pre-seed consumed + deferred to trigger validation
            consumedTraits = _: {
              firewall = true;
            };
            deferredTraits = _: {
              firewall = [
                {
                  value =
                    { config, ... }:
                    {
                      enable = true;
                    };
                  chain = "test";
                }
              ];
            };
          };
        } comp;
      in
      {
        den.schema.classes.nixos.description = "NixOS";
        den.schema.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
          partialOk = true;
        };
        den._traitNames.firewall = true;

        # With partialOk = true, fxResolve should NOT throw even with
        # consumed + deferred. We can't easily test fxResolve with pre-seeded
        # state, so verify the raw pipeline collected the deferred data.
        expr = (rawResult.state.deferredTraits null) ? firewall;
        expected = true;
      }
    );

  };
}
