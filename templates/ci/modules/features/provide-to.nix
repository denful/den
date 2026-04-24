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

  };
}
