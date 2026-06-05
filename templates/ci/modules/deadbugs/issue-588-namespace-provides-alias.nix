# Issue 588: `._` on a namespace root.
#
# `_` (alias for `provides`) lives on aspect leaves, so `den.aspects.foo._`
# worked but `foo._` — where `foo` is a *namespace* root (a container, not an
# aspect) — threw `attribute '_' missing`. A namespace root now exposes a
# synthetic `_` bundle whose includes are every aspect in the namespace, the
# container-level analog of an aspect's provides bundle.
{
  denTest,
  inputs,
  ...
}:
{
  flake.tests.deadbugs.issue-588 = {

    # Baseline from the report: `den.aspects.foo` is an ASPECT with nested
    # children; `den.aspects.foo._` is its provides bundle.
    test-direct-aspect-underscore = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.foo.bar.nixos.programs.localsend.enable = true;
        den.aspects.foo.barbar.nixos.system.stateVersion = "25.11";

        den.aspects.igloo.includes = [ den.aspects.foo._ ];

        expr = {
          localsend = igloo.programs.localsend.enable;
          stateVersion = igloo.system.stateVersion;
        };
        expected = {
          localsend = true;
          stateVersion = "25.11";
        };
      }
    );

    # The fix: `foo._` where `foo` is the NAMESPACE ROOT bundles all its
    # top-level aspects.
    test-namespace-root-underscore = denTest (
      {
        den,
        foo,
        igloo,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "foo" false) ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        foo.bar.nixos.programs.localsend.enable = true;
        foo.barbar.nixos.system.stateVersion = "25.11";

        den.aspects.igloo.includes = [ foo._ ];

        expr = {
          localsend = igloo.programs.localsend.enable;
          stateVersion = igloo.system.stateVersion;
        };
        expected = {
          localsend = true;
          stateVersion = "25.11";
        };
      }
    );

    # The bundle equals listing the namespace's aspects individually.
    test-namespace-explicit-list = denTest (
      {
        den,
        foo,
        igloo,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "foo" false) ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        foo.bar.nixos.programs.localsend.enable = true;
        foo.barbar.nixos.system.stateVersion = "25.11";

        den.aspects.igloo.includes = [
          foo.bar
          foo.barbar
        ];

        expr = {
          localsend = igloo.programs.localsend.enable;
          stateVersion = igloo.system.stateVersion;
        };
        expected = {
          localsend = true;
          stateVersion = "25.11";
        };
      }
    );

    # An aspect leaf inside a namespace still carries its own `_` (its nested
    # children self-provide), distinct from the namespace-root bundle.
    test-aspect-in-namespace-underscore = denTest (
      {
        den,
        ns,
        igloo,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        ns.app.bar.nixos.programs.localsend.enable = true;
        ns.app.barbar.nixos.system.stateVersion = "25.11";

        den.aspects.igloo.includes = [ ns.app._ ];

        expr = {
          localsend = igloo.programs.localsend.enable;
          stateVersion = igloo.system.stateVersion;
        };
        expected = {
          localsend = true;
          stateVersion = "25.11";
        };
      }
    );

    # The bundle excludes structural namespace keys (schema/classes/_): only
    # real aspects are pulled in, not the `classes` declaration.
    test-bundle-excludes-structural = denTest (
      {
        den,
        foo,
        igloo,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "foo" false) ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        foo.classes.extra.description = "structural, not an aspect";
        foo.bar.nixos.system.stateVersion = "25.11";

        den.aspects.igloo.includes = [ foo._ ];

        expr.stateVersion = igloo.system.stateVersion;
        expected.stateVersion = "25.11";
      }
    );

    # The computed `_` bundle must NOT be serialized into the exported
    # namespace, else re-import feeds a stale `_` into the read-only option.
    test-export-omits-underscore = denTest (
      { config, ns, ... }:
      {
        imports = [ (inputs.den.namespace "ns" true) ];
        ns.foo.nixos.system.stateVersion = "25.11";

        expr.exportHasUnderscore = config.flake.denful.ns ? _;
        expected.exportHasUnderscore = false;
      }
    );

    # Round-trip: forcing `_` on a RE-IMPORTED namespace must recompute the
    # bundle locally, not collide with the exported one (read-only "set
    # multiple times").
    test-reimport-namespace-bundle = denTest (
      { provider, ... }:
      {
        imports = [ (inputs.den.namespace "provider" [ inputs.provider ]) ];

        expr.hasIncludes = provider._ ? includes;
        expected.hasIncludes = true;
      }
    );

  };
}
