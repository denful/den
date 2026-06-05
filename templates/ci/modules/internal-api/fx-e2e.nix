{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-e2e = {

    # Basic pipeline: host with includes produces correct module count.
    test-host-with-includes = denTest (
      { den, ... }:
      let
        hostSelf = {
          name = "host";
          provides = { };
          nixos = {
            networking.hostName = "igloo";
          };
          includes = [
            {
              name = "desktop";
              meta = { };
              nixos = {
                wm = true;
              };
              includes = [ ];
            }
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = hostSelf;
          ctx = { };
        };
      in
      {
        # host.nixos + desktop.nixos = 2 imports
        expr = builtins.length result.imports;
        expected = 2;
      }
    );

    # Self-provide: emitAspectPolicies produces an include from provides.${name}.
    # In the full module system, ctx-apply handles this before the pipeline.
    # Here we test emitAspectPolicies directly.
    test-self-provider = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        hostSelf = {
          name = "host";
          into = _: { };
          provides = {
            host = ctx: {
              name = "host-provider";
              meta = { };
              nixos = {
                fromProvider = true;
              };
              includes = [ ];
            };
          };
          nixos = {
            base = true;
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.emitAspectPolicies hostSelf;
        result = fx.handle {
          handlers = {
            "emit-include" =
              { param, state }:
              {
                resume = [ param ];
                inherit state;
              };
          };
          state = { };
        } comp;
      in
      {
        expr = {
          hasProvider = builtins.isList result.value && builtins.length result.value >= 1;
          providerName = (builtins.head result.value).name;
          isSelfProvide = (builtins.head result.value).meta.selfProvide or false;
        };
        expected = {
          hasProvider = true;
          providerName = "host";
          isSelfProvide = true;
        };
      }
    );

    # Root adapter excludes aspect.
    test-root-adapter-excludes = denTest (
      { den, ... }:
      let
        wayland = {
          name = "wayland";
          meta = {
            provider = [ ];
          };
        };
        hostSelf = {
          name = "host";
          into = _: { };
          provides = { };
          meta = {
            handleWith = den.lib.aspects.fx.constraints.exclude wayland;
          };
          includes = [
            {
              name = "wayland";
              meta = {
                provider = [ ];
              };
              nixos = {
                wl = true;
              };
              includes = [ ];
            }
            {
              name = "x11";
              meta = {
                provider = [ ];
              };
              nixos = {
                x = true;
              };
              includes = [ ];
            }
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = hostSelf;
          ctx = { };
        };
      in
      {
        expr = builtins.length result.imports;
        expected = 1;
      }
    );

    # includeIf with hasAspect through full pipeline.
    test-includeIf-e2e = denTest (
      { den, ... }:
      let
        sops = {
          name = "sops";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        sopsConf = {
          name = "sops-conf";
          meta = {
            provider = [ ];
          };
          nixos = {
            sops = true;
          };
          includes = [ ];
        };
        hostSelf = {
          name = "host";
          into = _: { };
          provides = { };
          includes = [
            sops
            (den.lib.aspects.fx.includes.includeIf (ctx: ctx.hasAspect sops) [ sopsConf ])
          ];
        };
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = hostSelf;
          ctx = { };
        };
      in
      {
        expr = builtins.length result.imports;
        expected = 1;
      }
    );

  };
}
