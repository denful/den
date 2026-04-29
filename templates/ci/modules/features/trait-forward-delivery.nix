# Trait delivery through forward paths.
# evalConfig forwards use separate lib.evalModules without traitModule,
# so config._den.traits is missing. Non-evalConfig shares the final
# evalModules and works correctly.
{ denTest, lib, ... }:
{
  flake.tests.trait-forward-delivery = {

    # Regression guard: trait data collected in pipeline state survives
    # through fxResolve and is available in traitModule. Non-evalConfig
    # forwards share the final evalModules with traitModule, so class
    # modules can read config._den.traits via lazy thunks.
    test-non-evalConfig-trait-collection = denTest (
      { den, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = {
            name = "test-aspect";
            meta = { };
            greeting = "hello from igloo";
            includes = [ ];
          };
          ctx = { };
        };
        traits = result.state.traits null;
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.greeting = {
          description = "Test greeting trait";
          collection = "list";
        };

        # Verify trait data is collected in pipeline state
        expr = traits.greeting;
        expected = [ "hello from igloo" ];
      }
    );

    # Bug: evalConfig forward loses trait data.
    # mkDirectAspect calls lib.evalModules { modules = [freeformMod sourceModule]; }
    # without traitModule, so config._den.traits doesn't exist inside that
    # separate evaluation. The class module's `or ["MISSING"]` fallback fires.
    test-evalConfig-forward-loses-traits = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.traits.greeting = {
          description = "Test greeting trait";
          collection = "list";
        };

        den.schema.host.includes = [
          (
            { host, ... }:
            den._.forward {
              each = [ "nixos" ];
              fromClass = _: "custom";
              intoClass = _: host.class;
              intoPath = _: [ ];
              fromAspect = _: host.aspect;
              evalConfig = true;
            }
          )
        ];

        den.classes.custom = {
          description = "Custom class for evalConfig trait test";
        };

        den.aspects.igloo = {
          greeting = "hello from igloo";
          custom =
            { config, ... }:
            {
              networking.hostName = builtins.head (config._den.traits.greeting or [ "MISSING" ]);
            };
        };

        # If traits are delivered, hostName = "hello from igloo".
        # If traits are lost (the bug), hostName = "MISSING".
        expr = igloo.networking.hostName;
        expected = "hello from igloo";
      }
    );

  };
}
