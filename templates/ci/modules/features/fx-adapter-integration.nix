{
  denTest,
  inputs,
  lib,
  ...
}:
let
  # Run the unified pipeline for a given aspect.
  runPipeline =
    den:
    {
      ctx ? { },
      class ? "nixos",
    }:
    aspect:
    let
      fx = den.lib.fx;
      comp = fx.send "resolve" {
        inherit aspect;
        identity = den.lib.aspects.fx.identity.key aspect;
        ctx = { };
      };
    in
    fx.handle {
      handlers = den.lib.aspects.fx.pipeline.defaultHandlers { inherit ctx class; };
      state = den.lib.aspects.fx.pipeline.defaultState;
    } comp;
in
{
  flake.tests.fx-adapter-integration = {

    # Default pipeline collects class modules from tree.
    test-default-pipeline-collects-modules = denTest (
      { den, ... }:
      let
        root = {
          name = "root";
          meta = { };
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child1";
              meta = { };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
            {
              name = "child2";
              meta = { };
              nixos = {
                c = 3;
              };
              includes = [ ];
            }
          ];
        };
        result = runPipeline den { } root;
      in
      {
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 3; # root + child1 + child2 (emit-class fires for each)
      }
    );

    # exclude through full pipeline: tombstoned aspect's module not collected.
    test-exclude-through-pipeline = denTest (
      { den, ... }:
      let
        target = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        root = {
          name = "root";
          meta = {
            handleWith = den.lib.aspects.fx.constraints.exclude target;
          };
          includes = [
            {
              name = "keep";
              meta = {
                provider = [ ];
              };
              nixos = {
                a = 1;
              };
              includes = [ ];
            }
            {
              name = "drop";
              meta = {
                provider = [ ];
              };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        result = runPipeline den { } root;
      in
      {
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 1;
      }
    );

    # substitute through full pipeline.
    test-substitute-through-pipeline = denTest (
      { den, ... }:
      let
        old = {
          name = "old";
          meta = {
            provider = [ ];
          };
        };
        new = {
          name = "new";
          meta = {
            provider = [ ];
          };
          nixos = {
            replaced = true;
          };
          includes = [ ];
        };
        root = {
          name = "root";
          meta = {
            handleWith = den.lib.aspects.fx.constraints.substitute old new;
          };
          includes = [
            {
              name = "old";
              meta = {
                provider = [ ];
              };
              nixos = {
                original = true;
              };
              includes = [ ];
            }
          ];
        };
        result = runPipeline den { } root;
        tree = builtins.head result.value;
        children = tree.includes or [ ];
        names = map (c: c.name or "?") children;
      in
      {
        # Tombstone (~old) + replacement (new) both in tree, only new's module collected.
        expr = {
          importCount = builtins.length (
            (builtins.foldl' (
              acc: sd:
              lib.zipAttrsWith (_: builtins.concatLists) [
                acc
                sd
              ]
            ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
          );
          hasTombstone = builtins.any (n: n == "~old") names;
          hasReplacement = builtins.any (n: n == "new") names;
        };
        expected = {
          importCount = 1;
          hasTombstone = true;
          hasReplacement = true;
        };
      }
    );

    # includeIf with hasAspect through full pipeline.
    test-includeIf-through-pipeline = denTest (
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
        root = {
          name = "root";
          meta = { };
          includes = [
            sops
            (den.lib.aspects.fx.includes.includeIf (ctx: ctx.hasAspect sops) [ sopsConf ])
          ];
        };
        result = runPipeline den { } root;
      in
      {
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 1; # sopsConf.nixos
      }
    );

    # Context root adapter: adapter on root applies to all descendants.
    test-context-root-adapter = denTest (
      { den, ... }:
      let
        wayland = {
          name = "wayland";
          meta = {
            provider = [ ];
          };
        };
        root = {
          name = "igloo";
          meta = {
            handleWith = den.lib.aspects.fx.constraints.exclude wayland;
          };
          includes = [
            {
              name = "desktop";
              meta = {
                provider = [ ];
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
            }
          ];
        };
        result = runPipeline den { } root;
      in
      {
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 1; # only x11.nixos
      }
    );

    # Parametric aspect + adapter through pipeline.
    test-parametric-with-adapter = denTest (
      { den, ... }:
      let
        target = {
          name = "skip";
          meta = {
            provider = [ ];
          };
        };
        root = {
          name = "root";
          meta = {
            handleWith = den.lib.aspects.fx.constraints.exclude target;
          };
          includes = [
            {
              name = "web";
              meta = {
                provider = [ ];
              };
              __fn =
                { host }:
                {
                  nixos.hostName = host;
                  includes = [
                    {
                      name = "skip";
                      meta = {
                        provider = [ ];
                      };
                      nixos = {
                        x = 1;
                      };
                      includes = [ ];
                    }
                    {
                      name = "keep";
                      meta = {
                        provider = [ ];
                      };
                      nixos = {
                        y = 2;
                      };
                      includes = [ ];
                    }
                  ];
                };
              __args = {
                host = false;
              };
            }
          ];
        };
        result = runPipeline den {
          ctx = {
            host = "igloo";
          };
        } root;
      in
      {
        # web.nixos (hostName) + keep.nixos (y), skip is tombstoned
        expr = builtins.length (
          (builtins.foldl' (
            acc: sd:
            lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              sd
            ]
          ) { } (builtins.attrValues (result.state.scopedClassImports null))).nixos or [ ]
        );
        expected = 2;
      }
    );

  };
}
