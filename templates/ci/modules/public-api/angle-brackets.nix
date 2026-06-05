{ denTest, inputs, ... }:
{

  flake.tests.angle-brackets = {

    test-den-dot-access = denTest (
      { den, __findFile, ... }:
      {
        _module.args.__findFile = den.lib.__findFile;
        expr = <den.lib.parametric> ? atLeast;
        expected = true;
      }
    );

    test-den-slash-provides = denTest (
      {
        den,
        __findFile,
        lib,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;
        expr = lib.isFunction <den/import-tree/host>;
        expected = true;
      }
    );

    test-aspect-without-prefix = denTest (
      {
        den,
        __findFile,
        lib,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = { };
        expr = <igloo> ? provides;
        expected = true;
      }
    );

    test-aspect-provides = denTest (
      {
        den,
        __findFile,
        lib,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;
        den.aspects.foo.provides.bar.nixos = { };
        expr = <foo/bar> ? nixos;
        expected = true;
      }
    );

    test-namespace-access = denTest (
      {
        den,
        __findFile,
        ns,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;

        imports = [ (inputs.den.namespace "ns" true) ];

        ns.moo.silly = true;

        expr = <ns/moo> ? silly;
        expected = true;
      }
    );

    test-deep-nested-provides = denTest (
      {
        den,
        __findFile,
        igloo,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.provides.bar.provides.baz.nixos.programs.fish.enable = true;
        den.aspects.igloo.includes = [ <foo/bar/baz> ];

        expr = igloo.programs.fish.enable;
        expected = true;
      }
    );

    # Regression: non-parametric direct freeform child must not duplicate content.
    # Without __contentValues in structuralKeysSet, the content wrapper's
    # __contentValues key is classified as class content and emitted alongside
    # the forwarded nixos attr — applying overlays/config twice.
    test-direct-child-no-duplication = denTest (
      {
        den,
        __findFile,
        ns,
        igloo,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;

        imports = [ (inputs.den.namespace "ns" false) ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        ns.overlays.openrazer.nixos.networking.hostName = "overlay-host";

        den.aspects.igloo.includes = [ <ns/overlays/openrazer> ];

        expr = igloo.networking.hostName;
        expected = "overlay-host";
      }
    );

    # Regression: parametric function as direct freeform child of a namespace
    # aspect must resolve via angle-brackets identically to provides path.
    test-namespace-parametric-direct-child = denTest (
      {
        den,
        __findFile,
        ns,
        igloo,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;

        imports = [ (inputs.den.namespace "ns" false) ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        ns.apps.helix =
          { host, ... }:
          {
            nixos.networking.hostName = "${host.name}-helix";
          };

        den.aspects.igloo.includes = [ <ns/apps/helix> ];

        expr = igloo.networking.hostName;
        expected = "igloo-helix";
      }
    );

    # homeManager class via direct parametric freeform child + intermediate aspect
    # included at user scope (matching the real pattern: user aspect → everywhere → helix).
    test-namespace-parametric-hm-via-user-aspect = denTest (
      {
        den,
        __findFile,
        ns,
        tuxHm,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;

        imports = [ (inputs.den.namespace "ns" false) ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        ns.apps.helix =
          { host, ... }:
          {
            homeManager = _: {
              programs.helix.enable = true;
            };
          };

        ns.everywhere.includes = [ <ns/apps/helix> ];
        den.aspects.tux.includes = [ ns.everywhere ];

        expr = tuxHm.programs.helix.enable;
        expected = true;
      }
    );

    # Same as above but with provides path (should already work).
    test-namespace-parametric-provides-child = denTest (
      {
        den,
        __findFile,
        ns,
        igloo,
        ...
      }:
      {
        _module.args.__findFile = den.lib.__findFile;

        imports = [ (inputs.den.namespace "ns" false) ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        ns.apps.provides.helix =
          { host, ... }:
          {
            nixos.networking.hostName = "${host.name}-helix";
          };

        den.aspects.igloo.includes = [ <ns/apps/helix> ];

        expr = igloo.networking.hostName;
        expected = "igloo-helix";
      }
    );

  };

}
