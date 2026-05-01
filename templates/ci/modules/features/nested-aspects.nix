{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.nested-aspects = {

    # Direct nesting: igloo.tux = { homeManager... } works like provides.tux
    test-direct-nesting-basic = denTest (
      {
        den,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.tux = {
          homeManager.programs.git.enable = true;
        };
        den.aspects.tux.includes = [ den._.host-aspects ];

        expr = tuxHm.programs.git.enable;
        expected = true;
      }
    );

    # Direct nesting with nixos class key
    test-direct-nesting-nixos = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.servers = {
          nixos.networking.hostName = "nested-test";
        };

        expr = igloo.networking.hostName;
        expected = "nested-test";
      }
    );

    # Multi-level nesting: development.gui.vscode = { nixos... }
    test-multi-level-nesting = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.development = {
          gui = {
            nixos.networking.hostName = "multilevel";
          };
        };

        expr = igloo.networking.hostName;
        expected = "multilevel";
      }
    );

    # Nested aspect with trait emission
    test-nested-with-trait = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        aspect = {
          name = "parent";
          meta = { };
          child = {
            nixos = {
              networking.hostName = "trait-nested";
            };
            firewall = {
              port = 22;
            };
          };
          includes = [ ];
        };
        comp = den.lib.aspects.fx.aspect.aspectToEffect aspect;
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
        allTraits = builtins.foldl' (acc: v: acc // v) { } (
          builtins.attrValues (result.state.scopedTraits null)
        );
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.firewall = {
          description = "Firewall rules";
          collection = "list";
        };

        expr = {
          hasImports =
            builtins.length (
              (builtins.foldl' (
                acc: sd:
                lib.zipAttrsWith (_: builtins.concatLists) [
                  acc
                  sd
                ]
              ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
            ) > 0;
          hasTraitData = allTraits ? firewall;
          traitValue = allTraits.firewall;
        };
        expected = {
          hasImports = true;
          hasTraitData = true;
          traitValue = [
            { port = 22; }
          ];
        };
      }
    );

    # Nested aspect propagates scope handlers from parent
    test-nested-scope-propagation = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.web =
          { host, ... }:
          {
            servers = {
              nixos.networking.hostName = host.name;
            };
          };
        den.aspects.igloo.includes = [ den.aspects.web ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # provides still works (backward compat) — self-provide pattern
    test-provides-backward-compat = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.provides.igloo = {
          nixos.networking.hostName = "provides-compat";
        };

        expr = igloo.networking.hostName;
        expected = "provides-compat";
      }
    );

    # Nested aspect with parametric parent (scope propagation through __fn resolution)
    test-nested-parametric-parent = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.monitoring =
          { host, ... }:
          {
            agents = {
              nixos.networking.hostName = "${host.name}-monitored";
            };
          };
        den.aspects.igloo.includes = [ den.aspects.monitoring ];

        expr = igloo.networking.hostName;
        expected = "igloo-monitored";
      }
    );

  };
}
