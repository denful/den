{ denTest, ... }:
{
  flake.tests.provide-to = {

    # Aspect with provide-to has data collected in pipeline state.
    test-provide-to-collects-in-state = denTest (
      { den, ... }:
      let
        self = {
          name = "web-server";
          meta = { };
          nixos = { };
          "provide-to" = {
            http-backends = [
              {
                address = "10.0.0.1";
                port = 8080;
              }
            ];
          };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
        emissions = result.state.provideTo null;
      in
      {
        expr = builtins.length emissions;
        expected = 1;
      }
    );

    # Collected emission has correct shape.
    test-provide-to-emission-shape = denTest (
      { den, ... }:
      let
        self = {
          name = "web-server";
          meta = { };
          nixos = { };
          "provide-to" = {
            http-backends = [
              {
                address = "10.0.0.1";
                port = 8080;
              }
            ];
          };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
        emission = builtins.head (result.state.provideTo null);
      in
      {
        expr = {
          label = emission.label;
          aspectName = emission.aspectName;
          hasContent = emission.content != [ ];
          targetIsNull = emission.targetEntity == null;
        };
        expected = {
          label = "http-backends";
          aspectName = "web-server";
          hasContent = true;
          targetIsNull = true;
        };
      }
    );

    # Multiple provide-to labels produce multiple emissions.
    test-provide-to-multiple-labels = denTest (
      { den, ... }:
      let
        self = {
          name = "multi-provider";
          meta = { };
          nixos = { };
          "provide-to" = {
            http-backends = [ { port = 80; } ];
            dns-records = [ { type = "A"; } ];
          };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
        emissions = result.state.provideTo null;
        labels = builtins.sort (a: b: a < b) (map (e: e.label) emissions);
      in
      {
        expr = labels;
        expected = [
          "dns-records"
          "http-backends"
        ];
      }
    );

    # Aspect without provide-to produces no emissions.
    test-no-provide-to-no-emissions = denTest (
      { den, ... }:
      let
        self = {
          name = "plain-aspect";
          meta = { };
          nixos = {
            x = 1;
          };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
      in
      {
        expr = builtins.length (result.state.provideTo null);
        expected = 0;
      }
    );

    # provide-to is a structural key — not treated as a class key.
    test-provide-to-not-class-key = denTest (
      { den, ... }:
      let
        self = {
          name = "structural-test";
          meta = { };
          nixos = {
            x = 1;
          };
          "provide-to" = {
            http-backends = [ { port = 80; } ];
          };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
        # Only 1 class module (nixos), not 2 (provide-to is structural, not a class)
      in
      {
        expr = builtins.length (result.state.imports null);
        expected = 1;
      }
    );

    # Sibling policy (from == to) routes through provide-to, not local resolution.
    test-sibling-routes-to-provide-to = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg = { };

        den.policies.test-host-to-peer = {
          _core = true;
          from = "host";
          to = "host";
          as = "peer";
          resolve =
            { host, ... }: lib.filter (h: h.name != host.name) (lib.attrValues (den.hosts.x86_64-linux or { }));
        };

        expr =
          let
            igloo = den.hosts.x86_64-linux.igloo;
            result = den.lib.aspects.fx.pipeline.fxFullResolve {
              class = "nixos";
              self = den.lib.resolveStage "host" {
                inherit (igloo) system;
                host = igloo;
              };
              ctx = {
                inherit (igloo) system;
                host = igloo;
              };
            };
            emissions = result.state.provideTo null;
          in
          {
            hasEmissions = emissions != [ ];
            label = if emissions != [ ] then (builtins.head emissions).label else "";
          };
        expected = {
          hasEmissions = true;
          label = "peer";
        };
      }
    );

    # Fleet /etc/hosts: two hosts, each provides IP to peers via provide-to.
    # Distribution groups by target and produces handler bindings.
    test-fleet-hosts-distribution = denTest (
      { den, lib, ... }:
      let
        # Simulate provide-to emissions from two hosts
        emissions = [
          {
            label = "peer";
            content = {
              ip = "10.0.0.1";
              hostname = "igloo";
            };
            emitterCtx = { };
            aspectName = "fleet-hosts";
            targetEntity = {
              name = "iceberg";
            };
          }
          {
            label = "peer";
            content = {
              ip = "10.0.0.2";
              hostname = "iceberg";
            };
            emitterCtx = { };
            aspectName = "fleet-hosts";
            targetEntity = {
              name = "igloo";
            };
          }
        ];
        grouped = den.lib.aspects.fx.distributeProvideTo.groupByTarget emissions;
      in
      {
        expr = {
          targets = builtins.sort (a: b: a < b) (builtins.attrNames grouped);
          iglooData = (builtins.head grouped.igloo.peer).hostname;
          icebergData = (builtins.head grouped.iceberg.peer).hostname;
        };
        expected = {
          targets = [
            "iceberg"
            "igloo"
          ];
          iglooData = "iceberg";
          icebergData = "igloo";
        };
      }
    );

    # Haproxy backends: multiple sources provide http-backend data to a target.
    # Distribution accumulates data under the same label across sources.
    test-haproxy-backend-distribution = denTest (
      { den, lib, ... }:
      let
        emissions = [
          {
            label = "http-backends";
            content = [
              {
                address = "10.0.0.1";
                port = 8080;
                vhost = "example.com";
              }
            ];
            emitterCtx = { };
            aspectName = "example-site";
            targetEntity = {
              name = "lb";
            };
          }
          {
            label = "http-backends";
            content = [
              {
                address = "10.0.0.2";
                port = 8081;
                vhost = "foobar.com";
              }
            ];
            emitterCtx = { };
            aspectName = "foobar-site";
            targetEntity = {
              name = "lb";
            };
          }
        ];
        grouped = den.lib.aspects.fx.distributeProvideTo.groupByTarget emissions;
        handlers = den.lib.aspects.fx.distributeProvideTo.distribute emissions;
      in
      {
        expr = {
          backendCount = builtins.length grouped.lb.http-backends;
          hasHandler = handlers ? lb;
          vhosts = builtins.sort (a: b: a < b) (map (b: b.vhost) grouped.lb.http-backends);
        };
        expected = {
          backendCount = 2;
          hasHandler = true;
          vhosts = [
            "example.com"
            "foobar.com"
          ];
        };
      }
    );

    # Distribution produces constantHandler bindings usable by bind.fn.
    test-distribute-produces-handlers = denTest (
      { den, lib, ... }:
      let
        emissions = [
          {
            label = "http-backends";
            content = [
              {
                address = "10.0.0.1";
                port = 80;
              }
            ];
            emitterCtx = { };
            aspectName = "web";
            targetEntity = {
              name = "lb";
            };
          }
        ];
        handlers = den.lib.aspects.fx.distributeProvideTo.distribute emissions;
        # The handler for "lb" should contain an "http-backends" effect handler
        lbHandlers = handlers.lb;
      in
      {
        expr = {
          hasHttpBackends = lbHandlers ? http-backends;
        };
        expected = {
          hasHttpBackends = true;
        };
      }
    );

  };
}
