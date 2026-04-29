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

  };
}
