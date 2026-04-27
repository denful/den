# Tests for aspectKeyType — the unified freeform key type that dispatches on
# key name via class/trait registries. Currently all branches produce
# __contentValues (aspectContentType); after provides removal, the else
# branch switches to providerType for proper aspect shapes.
{
  denTest,
  inputs,
  lib,
  ...
}:
let
  collectHandlers = {
    "emit-class" =
      { param, state }:
      {
        resume = null;
        state = state // {
          classes = (state.classes or [ ]) ++ [ param ];
        };
      };
    "emit-trait" =
      { param, state }:
      {
        resume = null;
        state = state // {
          traits = (state.traits or [ ]) ++ [ param ];
        };
      };
    "emit-include" =
      { param, state }:
      {
        resume = [ (param.child or param) ];
        inherit state;
      };
    "register-constraint" =
      { param, state }:
      {
        resume = null;
        state = state // {
          constraints = (state.constraints or [ ]) ++ [ param ];
        };
      };
    "chain-push" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "chain-pop" =
      { param, state }:
      {
        resume = null;
        inherit state;
      };
    "resolve-complete" =
      { param, state }:
      {
        resume = param;
        inherit state;
      };
  };
in
{
  flake.tests.aspect-key-type = {

    # Class key (nixos is registered in den.classes) → provenance-wrapped __contentValues.
    test-class-key-shape = denTest (
      { den, ... }:
      let
        types = den.lib.aspects.mkAspectsType { providerPrefix = [ ]; };
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf types.aspectKeyType; }
            {
              nixos = {
                services.nginx.enable = true;
              };
            }
          ];
        };
        val = evaluated.config.nixos;
      in
      {
        expr = {
          hasContentValues = val ? __contentValues;
          hasProvider = val ? __provider;
          valueCount = builtins.length val.__contentValues;
          value = (builtins.head val.__contentValues).value;
        };
        expected = {
          hasContentValues = true;
          hasProvider = true;
          valueCount = 1;
          value = {
            services.nginx.enable = true;
          };
        };
      }
    );

    # Trait key (firewall registered via den.traits) → provenance-wrapped __contentValues.
    test-trait-key-shape = denTest (
      { den, ... }:
      let
        types = den.lib.aspects.mkAspectsType { providerPrefix = [ ]; };
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf types.aspectKeyType; }
            {
              firewall = {
                port = 80;
              };
            }
          ];
        };
        val = evaluated.config.firewall;
      in
      {
        den.traits.firewall.description = "Firewall ports";
        expr = {
          hasContentValues = val ? __contentValues;
          hasProvider = val ? __provider;
          valueCount = builtins.length val.__contentValues;
          value = (builtins.head val.__contentValues).value;
        };
        expected = {
          hasContentValues = true;
          hasProvider = true;
          valueCount = 1;
          value = {
            port = 80;
          };
        };
      }
    );

    # Unregistered key → aspectContentType (same as class/trait for now).
    # After provides removal, this branch switches to providerType for aspect shape.
    test-unregistered-key-shape = denTest (
      { den, ... }:
      let
        types = den.lib.aspects.mkAspectsType { providerPrefix = [ ]; };
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf types.aspectKeyType; }
            {
              to-users = {
                homeManager = {
                  programs.git.enable = true;
                };
              };
            }
          ];
        };
        val = evaluated.config.to-users;
      in
      {
        expr = {
          hasContentValues = val ? __contentValues;
          hasProvider = val ? __provider;
          valueCount = builtins.length val.__contentValues;
        };
        expected = {
          hasContentValues = true;
          hasProvider = true;
          valueCount = 1;
        };
      }
    );

    # Parametric function for unregistered key → also wrapped in __contentValues.
    test-parametric-unregistered-key-shape = denTest (
      { den, ... }:
      let
        types = den.lib.aspects.mkAspectsType { providerPrefix = [ ]; };
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf types.aspectKeyType; }
            {
              to-users =
                { user, ... }:
                {
                  homeManager.programs.git.enable = true;
                };
            }
          ];
        };
        val = evaluated.config.to-users;
        fn = (builtins.head val.__contentValues).value;
      in
      {
        expr = {
          hasContentValues = val ? __contentValues;
          isFunction = lib.isFunction fn;
        };
        expected = {
          hasContentValues = true;
          isFunction = true;
        };
      }
    );

    # Multi-def class key → both defs preserved in __contentValues.
    test-multi-def-class-key = denTest (
      { den, ... }:
      let
        types = den.lib.aspects.mkAspectsType { providerPrefix = [ ]; };
        evaluated = lib.evalModules {
          modules = [
            { freeformType = lib.types.lazyAttrsOf types.aspectKeyType; }
            { nixos.services.nginx.enable = true; }
            { nixos.networking.firewall.enable = true; }
          ];
        };
        val = evaluated.config.nixos;
        values = builtins.sort (a: b: builtins.toJSON a < builtins.toJSON b) (
          map (d: d.value) val.__contentValues
        );
      in
      {
        expr = {
          hasContentValues = val ? __contentValues;
          valueCount = builtins.length val.__contentValues;
          valuesHaveNginx = builtins.any (v: v ? services) values;
          valuesHaveFirewall = builtins.any (v: v ? networking) values;
        };
        expected = {
          hasContentValues = true;
          valueCount = 2;
          valuesHaveNginx = true;
          valuesHaveFirewall = true;
        };
      }
    );

    # E2E: aspect defined through den.aspects module config exercises the
    # pipeline with mixed keys — class emitted, trait emitted, all via
    # aspectKeyType dispatch.
    test-mixed-key-pipeline = denTest (
      { den, ... }:
      let
        aspect = den.aspects.mixed;
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = den.lib.fx.handle {
          handlers = collectHandlers;
          state = { };
        } comp;
      in
      {
        den.traits.firewall.description = "Firewall ports";
        den.aspects.mixed = {
          nixos.services.nginx.enable = true;
          firewall = {
            port = 80;
          };
        };
        expr = {
          nixosEmitted = builtins.any (c: c.class == "nixos") (result.state.classes or [ ]);
          firewallEmitted = builtins.any (t: t.trait == "firewall") (result.state.traits or [ ]);
        };
        expected = {
          nixosEmitted = true;
          firewallEmitted = true;
        };
      }
    );

  };
}
