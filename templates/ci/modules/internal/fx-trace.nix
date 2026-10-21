{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-trace = {

    test-structured-trace-fields = denTest (
      { den, ... }:
      let
        parent = {
          name = "root";
          meta = {
            provider = [ ];
          };
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child";
              meta = {
                provider = [ ];
              };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result =
          den.lib.aspects.fx.pipeline.mkPipeline
            {
              class = "nixos";
              extraHandlers = den.lib.aspects.fx.trace.structuredTraceHandler "nixos";
              extraState = {
                entries = [ ];
              };
            }
            {
              self = parent // {
                into = _: { };
                provides = { };
              };
              ctx = { };
            };
      in
      {
        expr =
          let
            names = map (e: e.name) result.state.entries;
          in
          {
            hasRoot = builtins.elem "root" names;
            hasChild = builtins.elem "child" names;
            allHaveClass = builtins.all (e: e.class == "nixos") result.state.entries;
          };
        expected = {
          hasRoot = true;
          hasChild = true;
          allHaveClass = true;
        };
      }
    );

    test-trace-excluded-aspect = denTest (
      { den, ... }:
      let
        target = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        parent = {
          name = "root";
          meta = {
            provider = [ ];
            handleWith = den.lib.aspects.fx.constraints.exclude target;
          };
          includes = [
            {
              name = "drop";
              meta = {
                provider = [ ];
              };
              nixos = { };
              includes = [ ];
            }
          ];
        };
        result =
          den.lib.aspects.fx.pipeline.mkPipeline
            {
              class = "nixos";
              extraHandlers = den.lib.aspects.fx.trace.structuredTraceHandler "nixos";
              extraState = {
                entries = [ ];
              };
            }
            {
              self = parent // {
                into = _: { };
                provides = { };
              };
              ctx = { };
            };
        excluded = builtins.filter (e: e.excluded) result.state.entries;
      in
      {
        expr =
          let
            excludedNames = map (e: e.name) excluded;
          in
          {
            hasExcluded = builtins.elem "~drop" excludedNames;
            excludedFromSet = (builtins.head excluded).excludedFrom != null;
          };
        expected = {
          hasExcluded = true;
          excludedFromSet = true;
        };
      }
    );

    test-ctx-trace-handler = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        comp = fx.send "ctx-traverse" {
          key = "host";
          self = {
            name = "host";
            provides = { };
          };
          ctx = { };
          prev = null;
          prevCtx = null;
        };
        result = fx.handle {
          handlers."ctx-traverse" =
            { param, state }:
            let
              item = {
                key = param.key;
                selfName = param.self.name or "<anon>";
              };
            in
            {
              resume = null;
              state = state // {
                ctxTrace = (state.ctxTrace or [ ]) ++ [ item ];
              };
            };
          state = {
            ctxTrace = [ ];
          };
        } comp;
      in
      {
        expr = (builtins.head result.state.ctxTrace).key;
        expected = "host";
      }
    );

    test-mkPipeline-with-trace = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        self = {
          name = "host";
          into = _: { };
          provides = { };
          nixos = {
            a = 1;
          };
          includes = [ ];
        };
        result =
          den.lib.aspects.fx.pipeline.mkPipeline
            {
              class = "nixos";
              extraHandlers = den.lib.aspects.fx.trace.structuredTraceHandler "nixos" // {
                "ctx-traverse" =
                  { param, state }:
                  {
                    resume = null;
                    inherit state;
                  };
              };
              extraState = {
                entries = [ ];
                ctxTrace = [ ];
              };
            }
            {
              inherit self;
              ctx = { };
            };
      in
      {
        expr = {
          hasHostEntry = builtins.any (e: e.name == "host") result.state.entries;
          allEntriesHaveClass = builtins.all (e: e.class == "nixos") result.state.entries;
          hasImports =
            ((builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
            ) != [ ];
        };
        expected = {
          hasHostEntry = true;
          allEntriesHaveClass = true;
          hasImports = true;
        };
      }
    );

    # Self-provide aspects (pre-included by ctx-apply) are traced and collected.
    test-self-provide-traced = denTest (
      { den, ... }:
      let
        # Simulate post-ctx-apply state: provides stays on the aspect,
        # but the provider is already materialized in includes.
        hostSelf = {
          name = "host";
          meta = { };
          provides = {
            host = ctx: {
              name = "host-provider";
              meta = { };
              nixos = {
                fromProv = true;
              };
              includes = [ ];
            };
          };
          nixos = {
            base = true;
          };
          includes = [
            {
              name = "host-provider";
              meta = { };
              nixos = {
                fromProv = true;
              };
              includes = [ ];
            }
          ];
        };
        result =
          den.lib.aspects.fx.pipeline.mkPipeline
            {
              class = "nixos";
              extraHandlers = den.lib.aspects.fx.trace.structuredTraceHandler "nixos";
              extraState = {
                entries = [ ];
              };
            }
            {
              self = hostSelf;
              ctx = { };
            };
        entryNames = map (e: e.name) result.state.entries;
      in
      {
        expr = {
          hasProvider = builtins.elem "host-provider" entryNames;
          hasHost = builtins.elem "host" entryNames;
          importCount = builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
          );
        };
        expected = {
          hasProvider = true;
          hasHost = true;
          # 3 = host (base), explicit host-provider include, self-provide result.
          # Self-provide now resolves positional-arg providers inline, so both
          # the explicit include and the self-provide produce modules.
          importCount = 3;
        };
      }
    );

    # tracingHandler collects entries + paths via resolve-complete.
    # classCollectorHandler collects imports via emit-class effects.
    test-tracingHandler-collects-entries-and-paths = denTest (
      { den, ... }:
      let
        parent = {
          name = "root";
          meta = {
            provider = [ ];
          };
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child";
              meta = {
                provider = [ ];
              };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result =
          den.lib.aspects.fx.pipeline.mkPipeline
            {
              class = "nixos";
              extraHandlers = den.lib.aspects.fx.trace.tracingHandler "nixos" // {
                "ctx-traverse" =
                  { param, state }:
                  {
                    resume = null;
                    inherit state;
                  };
              };
              extraState = {
                entries = [ ];
                paths = [ ];
                ctxTrace = [ ];
              };
            }
            {
              self = parent // {
                into = _: { };
                provides = { };
              };
              ctx = { };
            };
      in
      {
        expr = {
          hasEntries = result.state.entries != [ ];
          hasPaths = (result.state.pathSetByScope) null != { };
          hasImports =
            ((builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
            ) != [ ];
        };
        expected = {
          hasEntries = true;
          hasPaths = true;
          hasImports = true;
        };
      }
    );

    test-trace-parent-from-chain = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "root";
          meta = { };
          includes = [
            {
              name = "child";
              meta = { };
              includes = [ ];
            }
          ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.composeHandlers (den.lib.aspects.fx.pipeline.defaultHandlers
            {
              class = "nixos";
              ctx = { };
            }
          ) (den.lib.aspects.fx.trace.tracingHandler "nixos");
          state = den.lib.aspects.fx.pipeline.defaultState // {
            entries = [ ];
          };
        } comp;
        childEntry = lib.findFirst (e: e.name == "child") null result.state.entries;
      in
      {
        expr = childEntry.parent;
        expected = "root";
      }
    );

    test-trace-root-parent-null = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        root = {
          name = "root";
          meta = { };
          includes = [ ];
        };
        comp = fx.send "resolve" {
          aspect = root;
          identity = den.lib.aspects.fx.identity.key root;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.composeHandlers (den.lib.aspects.fx.pipeline.defaultHandlers
            {
              class = "nixos";
              ctx = { };
            }
          ) (den.lib.aspects.fx.trace.tracingHandler "nixos");
          state = den.lib.aspects.fx.pipeline.defaultState // {
            entries = [ ];
          };
        } comp;
        rootEntry = lib.findFirst (e: e.name == "root") null result.state.entries;
      in
      {
        expr = rootEntry.parent;
        expected = null;
      }
    );

    test-tracingHandler-entity-kind-seeded = denTest (
      { den, ... }:
      let
        entity = {
          name = "host";
          __entityKind = "host";
          meta = {
            provider = [ ];
          };
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child";
              meta = {
                provider = [ ];
              };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result =
          den.lib.aspects.fx.pipeline.mkPipeline
            {
              class = "nixos";
              extraHandlers = den.lib.aspects.fx.trace.tracingHandler "nixos";
              extraState = {
                entries = [ ];
                ctxTrace = [ ];
              };
            }
            {
              self = entity // {
                into = _: { };
                provides = { };
              };
              ctx = { };
            };
        hostEntry = lib.findFirst (e: e.name == "host") null result.state.entries;
        childEntry = lib.findFirst (e: e.name == "child") null result.state.entries;
      in
      {
        expr = {
          hostEntityKind = hostEntry.entityKind;
          childEntityKind = childEntry.entityKind;
          ctxTraceLength = builtins.length result.state.ctxTrace;
          ctxTraceKey = (builtins.head result.state.ctxTrace).key;
        };
        expected = {
          hostEntityKind = "host";
          childEntityKind = "host";
          ctxTraceLength = 1;
          ctxTraceKey = "host";
        };
      }
    );

    test-tracingHandler-record-fired = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        comp = fx.send "record-fired" {
          entityKind = "host";
          firedPolicies = {
            host-to-users = true;
            host-to-default = true;
          };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.composeHandlers (den.lib.aspects.fx.pipeline.defaultHandlers
            {
              class = "nixos";
              ctx = { };
            }
          ) (den.lib.aspects.fx.trace.tracingHandler "nixos");
          state = den.lib.aspects.fx.pipeline.defaultState // {
            entries = [ ];
            ctxTrace = [ ];
          };
        } comp;
        policyEntries = builtins.filter (e: e.isPolicyDispatch or false) result.state.entries;
        policyNames = lib.sort (a: b: a < b) (map (e: e.policyName) policyEntries);
      in
      {
        expr = {
          count = builtins.length policyEntries;
          names = policyNames;
          fromKind = (builtins.head policyEntries).from;
          toIsNull = (builtins.head policyEntries).to == null;
        };
        expected = {
          count = 2;
          names = [
            "host-to-default"
            "host-to-users"
          ];
          fromKind = "host";
          toIsNull = true;
        };
      }
    );

  };
}
