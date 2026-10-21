{ denTest, lib, ... }:
{
  flake.tests.aspect-path = {

    test-aspectPath-named = denTest (
      { den, ... }:
      {
        den.aspects.foo.nixos = { };
        expr = den.lib.aspects.fx.identity.aspectPath den.aspects.foo;
        expected = [ "foo" ];
      }
    );

    test-aspectPath-with-provider = denTest (
      { den, ... }:
      {
        den.aspects.monitoring = {
          nixos = { };
          provides.node-exporter.nixos = { };
        };
        expr = den.lib.aspects.fx.identity.aspectPath den.aspects.monitoring.provides.node-exporter;
        expected = [
          "monitoring"
          "node-exporter"
        ];
      }
    );

    # excludeAspect: excluded include becomes a tombstone (visible in trace)
    test-excludeAspect-tombstone-in-trace = denTest (
      { den, trace, ... }:
      {
        den.aspects.foo.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.foo.meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.baz;
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };

        expr = trace "nixos" den.aspects.foo;
        # baz appears as tombstone (~baz, no children)
        expected.trace = [
          "foo"
          [ "bar" ]
          [ "~baz" ]
        ];
      }
    );

    # excludeAspect: tombstone contributes no modules to the build
    test-excludeAspect-no-modules = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.igloo.meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.baz;
        den.aspects.bar.nixos.environment.sessionVariables.msg = "bar";
        den.aspects.baz.nixos.environment.sessionVariables.msg = "baz";

        # only bar's module is included, baz is excluded
        expr = igloo.environment.sessionVariables.msg;
        expected = "bar";
      }
    );

    # excludeAspect: propagates through subtree
    test-excludeAspect-propagates-to-subtree = denTest (
      { den, trace, ... }:
      {
        den.aspects.root.includes = [ den.aspects.role ];
        den.aspects.root.meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.baz;
        den.aspects.role.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };

        expr = trace "nixos" den.aspects.root;
        # baz tombstone appears in role's subtree
        expected.trace = [
          "root"
          [
            "role"
            [ "bar" ]
            [ "~baz" ]
          ]
        ];
      }
    );

    # excludeAspect: by provider path
    test-excludeAspect-by-provider = denTest (
      { den, trace, ... }:
      {
        den.aspects.monitoring = {
          nixos = { };
          provides.node-exporter.nixos = { };
          provides.alerting.nixos = { };
        };
        den.aspects.server.includes = with den.aspects; [
          monitoring
          monitoring.provides.node-exporter
          monitoring.provides.alerting
        ];
        den.aspects.server.meta.handleWith =
          den.lib.aspects.fx.constraints.exclude den.aspects.monitoring.provides.node-exporter;

        expr = trace "nixos" den.aspects.server;
        # node-exporter tombstone visible, alerting kept
        expected.trace = [
          "server"
          [ "monitoring" ]
          [ "~node-exporter" ]
          [ "alerting" ]
        ];
      }
    );

    # excludeAspect: excluding a parent also excludes its providers
    test-excludeAspect-cascades-to-providers = denTest (
      { den, trace, ... }:
      {
        den.aspects.monitoring = {
          nixos = { };
          provides.node-exporter.nixos = { };
          provides.alerting.nixos = { };
        };
        den.aspects.server.includes = with den.aspects; [
          monitoring
          monitoring.provides.node-exporter
          monitoring.provides.alerting
        ];
        den.aspects.server.meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.monitoring;

        expr = trace "nixos" den.aspects.server;
        # monitoring and all its providers excluded
        expected.trace = [
          "server"
          [ "~monitoring" ]
          [ "~node-exporter" ]
          [ "~alerting" ]
        ];
      }
    );

    # substituteAspect: replaced include becomes tombstone + replacement
    test-substituteAspect-replaces = denTest (
      { den, trace, ... }:
      {
        den.aspects.foo.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.foo.meta.handleWith =
          den.lib.aspects.fx.constraints.substitute den.aspects.bar den.aspects.qux;
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };
        den.aspects.qux.nixos = { };

        expr = trace "nixos" den.aspects.foo;
        # bar tombstone + qux replacement, baz unchanged
        expected.trace = [
          "foo"
          [ "~bar" ]
          [ "qux" ]
          [ "baz" ]
        ];
      }
    );

    # substituteAspect: replacement modules are used in build
    test-substituteAspect-build-uses-replacement = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [ den.aspects.bar ];
        den.aspects.igloo.meta.handleWith =
          den.lib.aspects.fx.constraints.substitute den.aspects.bar den.aspects.qux;
        den.aspects.bar.nixos.environment.sessionVariables.msg = "bar";
        den.aspects.qux.nixos.environment.sessionVariables.msg = "qux";

        # qux's module is used, not bar's
        expr = igloo.environment.sessionVariables.msg;
        expected = "qux";
      }
    );

    # substituteAspect: propagates through subtree
    test-substituteAspect-propagates = denTest (
      { den, trace, ... }:
      {
        den.aspects.root.includes = [ den.aspects.role ];
        den.aspects.root.meta.handleWith =
          den.lib.aspects.fx.constraints.substitute den.aspects.baz den.aspects.qux;
        den.aspects.role.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };
        den.aspects.qux.nixos = { };

        expr = trace "nixos" den.aspects.root;
        # baz tombstone + qux in role's subtree
        expected.trace = [
          "root"
          [
            "role"
            [ "bar" ]
            [ "~baz" ]
            [ "qux" ]
          ]
        ];
      }
    );

    # perHost parametric aspects should appear in trace by name
    test-perHost-visible-in-trace = denTest (
      { den, trace, ... }:
      {
        den.aspects.role.includes = with den.aspects; [
          leaf
          param
        ];
        den.aspects.leaf.nixos = { };
        den.aspects.param =
          { host, ... }:
          {
            nixos = { };
          };

        expr = trace "nixos" den.aspects.role;
        # §6: the trace pipeline runs at the ROOT scope (ctx = {}). A plain
        # { host, ... } aspect there destructures an entity kind that is neither
        # in-ctx nor a descendant → misplaced → inert (emits no nixos content).
        # It still appears in the trace by NAME as a childless node `["param"]`:
        # trace visibility tracks the include graph, not emission. (The prior
        # cross-scope deferral carrier is gone, but structural visibility remains.)
        expected.trace = [
          "role"
          [ "leaf" ]
          [ "param" ]
        ];
      }
    );

  };
}
