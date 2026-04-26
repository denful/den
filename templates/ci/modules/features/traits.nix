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
        expr = result.value;
        expected = null;
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

  };
}
