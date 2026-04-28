{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-full-pipeline = {

    # Minimal: single aspect with nixos config, collects module.
    test-minimal-pipeline = denTest (
      { den, ... }:
      let
        self = {
          name = "host";
          meta = { };
          nixos = {
            networking.hostName = "test";
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
        expr = builtins.length ((result.state.classImports null).nixos or [ ]);
        expected = 1;
      }
    );

    # Root + child: both class modules collected.
    test-root-and-child-modules = denTest (
      { den, ... }:
      let
        self = {
          name = "host";
          meta = { };
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child";
              meta = { };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
      in
      {
        expr = builtins.length ((result.state.classImports null).nixos or [ ]);
        expected = 2;
      }
    );

    # fxResolve returns { imports } shape.
    test-fxResolve-shape = denTest (
      { den, ... }:
      let
        self = {
          name = "host";
          meta = { };
          nixos = {
            a = 1;
          };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
      in
      {
        expr = result ? imports && builtins.isList result.imports;
        expected = true;
      }
    );

    # Constraint (exclude) through full pipeline.
    test-adapter-through-pipeline = denTest (
      { den, ... }:
      let
        target = {
          name = "drop";
          meta.provider = [ ];
        };
        self = {
          name = "host";
          meta = {
            handleWith = den.lib.aspects.fx.constraints.exclude target;
          };
          includes = [
            {
              name = "keep";
              meta.provider = [ ];
              nixos = {
                a = 1;
              };
              includes = [ ];
            }
            {
              name = "drop";
              meta.provider = [ ];
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
      in
      {
        expr = builtins.length result.imports;
        expected = 1;
      }
    );

    # Multi-class collection: emissions for two classes collected in one pass.
    test-multi-class-collection = denTest (
      { den, ... }:
      let
        self = {
          name = "host";
          meta = { };
          nixos = {
            networking.hostName = "test";
          };
          homeManager = {
            programs.git.enable = true;
          };
          includes = [ ];
        };
        # Use fxFullResolve to access raw state (fxResolve returns a module shape).
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
        classImports = result.state.classImports null;
        # Also verify fxResolve backwards compat
        resolveResult = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
      in
      {
        expr = {
          # fxResolve backwards compat: imports has nixos content
          hasImports = builtins.length resolveResult.imports > 0;
          # Multi-class: both classes collected
          hasNixos = classImports ? nixos && classImports.nixos != [ ];
          hasHomeManager = classImports ? homeManager && classImports.homeManager != [ ];
        };
        expected = {
          hasImports = true;
          hasNixos = true;
          hasHomeManager = true;
        };
      }
    );

    # Parametric child through full pipeline.
    test-parametric-through-pipeline = denTest (
      { den, ... }:
      let
        self = {
          name = "host";
          meta = { };
          includes = [
            {
              name = "web";
              meta = { };
              __fn =
                { host }:
                {
                  nixos.hostName = host;
                };
              __args = {
                host = false;
              };
            }
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = {
            host = "igloo";
          };
        };
      in
      {
        expr = builtins.length ((result.state.classImports null).nixos or [ ]);
        expected = 1;
      }
    );

  };
}
