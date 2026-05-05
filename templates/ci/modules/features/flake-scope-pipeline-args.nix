{ denTest, ... }:
{
  flake.tests.flake-scope-pipeline-args = {

    # pipelineOnly on attrset preserves all attributes and adds collisionPolicy.
    test-pipeline-only-preserves-attrs = denTest (
      { den, ... }:
      let
        original = {
          mkIf = cond: val: if cond then val else { };
          foo = "bar";
        };
        tagged = den.lib.policy.pipelineOnly original;
      in
      {
        expr = {
          preservesFoo = tagged.foo;
          preservesMkIf = (tagged.mkIf true "yes");
          hasPolicy = tagged.collisionPolicy;
        };
        expected = {
          preservesFoo = "bar";
          preservesMkIf = "yes";
          hasPolicy = "class-wins";
        };
      }
    );

    # pipelineOnly on non-attrset (function) wraps with __functor.
    test-pipeline-only-non-attrset = denTest (
      { den, ... }:
      let
        fn = x: x + 1;
        tagged = den.lib.policy.pipelineOnly fn;
      in
      {
        expr = {
          callable = tagged 5;
          hasPolicy = tagged.collisionPolicy;
          isAttrs = builtins.isAttrs tagged;
        };
        expected = {
          callable = 6;
          hasPolicy = "class-wins";
          isAttrs = true;
        };
      }
    );

    # Aspect receives lib from flake-scope enrichment policy.
    test-aspect-receives-lib = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.flake-scope ];

        den.aspects.use-lib =
          { host, lib, ... }:
          {
            nixos = lib.mkIf (host.class == "nixos") {
              environment.variables.GOT_LIB = "yes";
            };
          };

        den.aspects.igloo.includes = [ den.aspects.use-lib ];

        expr = igloo.environment.variables.GOT_LIB;
        expected = "yes";
      }
    );

    # Aspect receives inputs from flake-scope enrichment policy.
    test-aspect-receives-inputs = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.flake-scope ];

        den.aspects.use-inputs =
          { inputs, ... }:
          {
            nixos.environment.variables.HAS_SELF = if inputs ? self then "yes" else "no";
          };

        den.aspects.igloo.includes = [ den.aspects.use-inputs ];

        expr = igloo.environment.variables.HAS_SELF;
        expected = "yes";
      }
    );

    # Aspect receives den from flake-scope enrichment policy.
    test-aspect-receives-den = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.flake-scope ];

        den.aspects.use-den =
          { den, ... }:
          {
            nixos.environment.variables.HAS_LIB = if den ? lib then "yes" else "no";
          };

        den.aspects.igloo.includes = [ den.aspects.use-den ];

        expr = igloo.environment.variables.HAS_LIB;
        expected = "yes";
      }
    );

    # Class module requests lib — NixOS also provides lib via _module.args.
    # collisionPolicy = "class-wins" should let NixOS lib win silently.
    test-class-module-lib-collision-silent = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.flake-scope ];

        den.aspects.collision-test = {
          nixos =
            { lib, config, ... }:
            {
              environment.variables.LIB_WORKS = if lib ? mkIf then "yes" else "no";
            };
        };

        den.aspects.igloo.includes = [ den.aspects.collision-test ];

        expr = igloo.environment.variables.LIB_WORKS;
        expected = "yes";
      }
    );

    # Optional lib arg receives enrichment value, not the default.
    test-optional-lib-arg = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.flake-scope ];

        den.aspects.optional-lib =
          {
            lib ? null,
            ...
          }:
          {
            nixos.environment.variables.LIB_PRESENT = if lib != null then "yes" else "no";
          };

        den.aspects.igloo.includes = [ den.aspects.optional-lib ];

        expr = igloo.environment.variables.LIB_PRESENT;
        expected = "yes";
      }
    );

    # Mixed collision policies: lib has class-wins (from pipelineOnly),
    # custom enrichment has default policy. Each arg resolves independently.
    test-mixed-collision-policies = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.custom-enrichment =
          { host, ... }:
          [
            (den.lib.policy.resolve {
              myArg = host.class;
            })
          ];

        den.default.includes = [
          den.provides.flake-scope
          den.policies.custom-enrichment
        ];

        den.aspects.mixed-collision = {
          nixos =
            { lib, myArg, ... }:
            {
              environment.variables.MIXED_LIB = if lib ? mkIf then "yes" else "no";
              environment.variables.MIXED_ARG = myArg;
            };
        };

        den.aspects.igloo.includes = [ den.aspects.mixed-collision ];

        expr = {
          lib = igloo.environment.variables.MIXED_LIB;
          arg = igloo.environment.variables.MIXED_ARG;
        };
        expected = {
          lib = "yes";
          arg = "nixos";
        };
      }
    );

    # Forward sub-pipelines re-dispatch policies (parent aspectPolicies
    # injected via extraState). Enrichment from flake-scope should be
    # available in the forwarded custom class resolved via evalConfig.
    test-forward-sub-pipeline-receives-enrichment = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.flake-scope ];

        den.classes.variables = {
          description = "Custom variables class for forward enrichment test";
        };

        den.schema.host.includes = [
          (
            { host, ... }:
            den._.forward {
              each = [ "nixos" ];
              fromClass = _: "variables";
              intoClass = _: host.class;
              intoPath = _: [
                "environment"
                "sessionVariables"
              ];
              fromAspect = _: host.aspect;
              evalConfig = true;
            }
          )
        ];

        den.aspects.igloo.variables =
          { lib, ... }:
          {
            FORWARD_LIB = if lib ? mkIf then "yes" else "no";
          };

        expr = igloo.environment.sessionVariables.FORWARD_LIB;
        expected = "yes";
      }
    );

    # Enrichment-only keys (lib from flake-scope) must be handled correctly
    # when both parametric wrapper and class module use lib. The wrapper
    # gets pipeline-injected lib (with collisionPolicy), the class module
    # gets NixOS-native lib.
    test-enrichment-stripping-at-class-boundary = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.provides.flake-scope ];

        den.aspects.layered =
          { host, lib, ... }:
          {
            nixos =
              { config, lib, ... }:
              {
                environment.variables.LAYERED = lib.optionalString (host.class == "nixos") "yes";
              };
          };

        den.aspects.igloo.includes = [ den.aspects.layered ];

        expr = igloo.environment.variables.LAYERED;
        expected = "yes";
      }
    );

  };
}
