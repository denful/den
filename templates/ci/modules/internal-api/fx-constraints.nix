{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-constraints = {

    test-exclude-declaration = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ref = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        decl = den.lib.aspects.fx.constraints.exclude ref;
      in
      {
        expr = {
          type = decl.type;
          identity = decl.identity;
        };
        expected = {
          type = "exclude";
          identity = "drop";
        };
      }
    );

    test-substitute-declaration = denTest (
      { den, ... }:
      let
        ref = {
          name = "old";
          meta = {
            provider = [ ];
          };
        };
        replacement = {
          name = "new";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        decl = den.lib.aspects.fx.constraints.substitute ref replacement;
      in
      {
        expr = {
          type = decl.type;
          identity = decl.identity;
          replacementName = decl.replacementName;
        };
        expected = {
          type = "substitute";
          identity = "old";
          replacementName = "new";
        };
      }
    );

    test-exclude-via-registry = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ref = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        decl = den.lib.aspects.fx.constraints.exclude ref;
        # Register then check-constraint
        comp = fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
          _: fx.send "check-constraint" "drop"
        );
        result = fx.handle {
          handlers = den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
            scopedIncludesChain = _: { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-check-constraint-default-keep = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        comp = fx.send "check-constraint" "unknown";
        result = fx.handle {
          handlers = den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
            scopedIncludesChain = _: { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "keep";
      }
    );

    test-substitute-via-registry = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ref = {
          name = "old";
          meta = {
            provider = [ ];
          };
        };
        replacement = {
          name = "new";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        decl = den.lib.aspects.fx.constraints.substitute ref replacement;
        comp = fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
          _: fx.send "check-constraint" "old"
        );
        result = fx.handle {
          handlers = den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
            scopedIncludesChain = _: { };
          };
        } comp;
      in
      {
        expr = {
          action = result.value.action;
          replacementName = result.value.replacement.name;
        };
        expected = {
          action = "substitute";
          replacementName = "new";
        };
      }
    );

    # Test classCollectorHandler collects imports via emit-class effects through the pipeline.
    test-classCollectorHandler-collects-imports = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        parent = {
          name = "root";
          meta = { };
          includes = [
            {
              name = "a";
              meta = { };
              nixos = {
                enable = true;
              };
              includes = [ ];
            }
            {
              name = "b";
              meta = { };
              includes = [ ];
            }
          ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
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

    test-collectPaths-excludes-tombstones = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        target = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        parent = {
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
              includes = [ ];
            }
            {
              name = "drop";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
          ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
      in
      {
        # root + keep = 2 paths in pathSet, drop is tombstoned and excluded
        expr = builtins.length (builtins.attrNames ((result.state.pathSet) null));
        expected = 2;
      }
    );

    test-exclude-default-scope = denTest (
      { den, ... }:
      let
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = den.lib.aspects.fx.constraints.exclude ref;
      in
      {
        expr = decl.scope;
        expected = "subtree";
      }
    );

    test-exclude-global-scope = denTest (
      { den, ... }:
      let
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = den.lib.aspects.fx.constraints.exclude.global ref;
      in
      {
        expr = {
          type = decl.type;
          scope = decl.scope;
          identity = decl.identity;
        };
        expected = {
          type = "exclude";
          scope = "global";
          identity = "drop";
        };
      }
    );

    test-substitute-default-scope = denTest (
      { den, ... }:
      let
        ref = {
          name = "old";
          meta.provider = [ ];
        };
        replacement = {
          name = "new";
          meta.provider = [ ];
          includes = [ ];
        };
        decl = den.lib.aspects.fx.constraints.substitute ref replacement;
      in
      {
        expr = decl.scope;
        expected = "subtree";
      }
    );

    test-substitute-global-scope = denTest (
      { den, ... }:
      let
        ref = {
          name = "old";
          meta.provider = [ ];
        };
        replacement = {
          name = "new";
          meta.provider = [ ];
          includes = [ ];
        };
        decl = den.lib.aspects.fx.constraints.substitute.global ref replacement;
      in
      {
        expr = decl.scope;
        expected = "global";
      }
    );

    test-filter-default-scope = denTest (
      { den, ... }:
      let
        decl = den.lib.aspects.fx.constraints.filterBy (_: true);
      in
      {
        expr = decl.scope;
        expected = "subtree";
      }
    );

    test-filter-global-scope = denTest (
      { den, ... }:
      let
        decl = den.lib.aspects.fx.constraints.filterBy.global (_: true);
      in
      {
        expr = decl.scope;
        expected = "global";
      }
    );

    test-scoped-exclude-in-subtree = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = den.lib.aspects.fx.constraints.exclude ref;
        comp = fx.bind (fx.send "chain-push" { identity = "parent"; }) (
          _:
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-push" { identity = "child"; }) (
              _:
              fx.send "check-constraint" {
                identity = "drop";
                aspect = null;
              }
            )
          )
        );
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.handlers.chainHandler // den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-scoped-exclude-outside-subtree = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = den.lib.aspects.fx.constraints.exclude ref;
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _:
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-constraint" {
                  identity = "drop";
                  aspect = null;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.handlers.chainHandler // den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "keep";
      }
    );

    test-global-exclude-ignores-chain = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = den.lib.aspects.fx.constraints.exclude.global ref;
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _:
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-constraint" {
                  identity = "drop";
                  aspect = null;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.handlers.chainHandler // den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-scoped-filter-in-subtree = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        decl = den.lib.aspects.fx.constraints.filterBy (a: a.name != "drop");
        aspect = {
          name = "drop";
          meta.provider = [ ];
        };
        comp = fx.bind (fx.send "chain-push" { identity = "parent"; }) (
          _:
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.send "check-constraint" {
              identity = "drop";
              inherit aspect;
            }
          )
        );
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.handlers.chainHandler // den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-scoped-filter-outside-subtree = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        decl = den.lib.aspects.fx.constraints.filterBy (a: a.name != "drop");
        aspect = {
          name = "drop";
          meta.provider = [ ];
        };
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _:
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-constraint" {
                  identity = "drop";
                  inherit aspect;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.handlers.chainHandler // den.lib.aspects.fx.handlers.constraintRegistryHandler;
          state = {
            currentScope = "__test";
            scopedIncludesChain = _: { };
            scopedConstraintRegistry = _: { };
            scopedConstraintFilters = _: { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "keep";
      }
    );

    # classCollectorHandler skips tombstoned aspects (excluded = true means no emit-class).
    test-classCollectorHandler-skips-tombstones = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        target = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        parent = {
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
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers = den.lib.aspects.fx.pipeline.defaultHandlers {
            class = "nixos";
            ctx = { };
          };
          state = den.lib.aspects.fx.pipeline.defaultState;
        } comp;
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

    # excludes: exclude via list of refs
    test-excludes-sugar = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        target = {
          name = "drop";
          meta.provider = [ ];
        };
        parent = {
          name = "root";
          meta = { };
          excludes = [ target ];
          includes = [
            {
              name = "keep";
              meta.provider = [ ];
              includes = [ ];
            }
            {
              name = "drop";
              meta.provider = [ ];
              includes = [ ];
            }
          ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.pipeline.composeHandlers
              (den.lib.aspects.fx.pipeline.defaultHandlers {
                class = "nixos";
                ctx = { };
              })
              {
                "resolve-complete" =
                  { param, state }:
                  {
                    resume = param;
                    state = state // {
                      excluded = (state.excluded or [ ]) ++ (lib.optional (param.meta.excluded or false) param.name);
                    };
                  };
              };
          state = den.lib.aspects.fx.pipeline.defaultState // {
            excluded = [ ];
          };
        } comp;
      in
      {
        expr = result.state.excluded;
        expected = [ "~drop" ];
      }
    );

    # meta.handleWith as list of multiple handlers
    test-handleWith-list = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        targetA = {
          name = "a";
          meta.provider = [ ];
        };
        targetB = {
          name = "b";
          meta.provider = [ ];
        };
        parent = {
          name = "root";
          meta = {
            handleWith = [
              (den.lib.aspects.fx.constraints.exclude targetA)
              (den.lib.aspects.fx.constraints.exclude targetB)
            ];
          };
          includes = [
            {
              name = "a";
              meta.provider = [ ];
              includes = [ ];
            }
            {
              name = "b";
              meta.provider = [ ];
              includes = [ ];
            }
            {
              name = "c";
              meta.provider = [ ];
              includes = [ ];
            }
          ];
        };
        comp = fx.send "resolve" {
          aspect = parent;
          identity = den.lib.aspects.fx.identity.key parent;
          ctx = { };
        };
        result = fx.handle {
          handlers =
            den.lib.aspects.fx.pipeline.composeHandlers
              (den.lib.aspects.fx.pipeline.defaultHandlers {
                class = "nixos";
                ctx = { };
              })
              {
                "resolve-complete" =
                  { param, state }:
                  {
                    resume = param;
                    state = state // {
                      excluded = (state.excluded or [ ]) ++ (lib.optional (param.meta.excluded or false) param.name);
                    };
                  };
              };
          state = den.lib.aspects.fx.pipeline.defaultState // {
            excluded = [ ];
          };
        } comp;
      in
      {
        expr = builtins.sort builtins.lessThan result.state.excluded;
        expected = [
          "~a"
          "~b"
        ];
      }
    );

  };
}
