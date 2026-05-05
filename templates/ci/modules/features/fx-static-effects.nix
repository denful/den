{
  denTest,
  lib,
  ...
}:
{
  flake.tests.fx-static-effects = {

    # classify: partitions aspect keys into class keys and nested keys.
    test-classify-class-key = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "test";
          meta = { };
          includes = [ ];
          nixos = _: { imports = [ ]; };
        };
        comp = fx.send "classify" {
          inherit aspect;
          targetClass = null;
        };
        result = fx.handle {
          handlers = handlers.classifyHandler;
          state = { };
        } comp;
      in
      {
        expr = builtins.length result.value.classKeys;
        expected = 1;
      }
    );

    # classify: nested keys are detected for attrsets with recognized sub-keys.
    test-classify-returns-nested-keys = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "test";
          meta = { };
          includes = [ ];
          nixos = _: { imports = [ ]; };
        };
        comp = fx.send "classify" {
          inherit aspect;
          targetClass = null;
        };
        result = fx.handle {
          handlers = handlers.classifyHandler;
          state = { };
        } comp;
      in
      {
        expr = result.value.nestedKeys;
        expected = [ ];
      }
    );

    # classify: structural keys are excluded from classification.
    test-classify-excludes-structural = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "test";
          meta = { };
          includes = [ ];
          description = "should be excluded";
        };
        comp = fx.send "classify" {
          inherit aspect;
          targetClass = null;
        };
        result = fx.handle {
          handlers = handlers.classifyHandler;
          state = { };
        } comp;
      in
      {
        # name, meta, includes, description are all structural
        expr = result.value.classKeys;
        expected = [ ];
      }
    );

    # emit-classes: sends emit-class effects for each class key module.
    test-emit-classes-sends-effects = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "test";
          meta = { };
          nixos = _: { imports = [ ]; };
        };
        # Count emit-class effects via a stub handler.
        emitClassStub = {
          "emit-class" =
            { param, state }:
            {
              resume = null;
              state = state // {
                emitCount = (state.emitCount or 0) + 1;
                lastClass = param.class;
              };
            };
        };
        comp = fx.send "emit-classes" {
          inherit aspect;
          classKeys = [ "nixos" ];
          identity = "test";
        };
        result = fx.handle {
          handlers = handlers.emitClassesHandler // emitClassStub;
          state = { };
        } comp;
      in
      {
        expr = {
          count = result.state.emitCount;
          class = result.state.lastClass;
        };
        expected = {
          count = 1;
          class = "nixos";
        };
      }
    );

    # emit-classes: multiple class keys each produce emit-class effects.
    test-emit-classes-multiple-keys = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "multi";
          meta = { };
          nixos = _: { };
          home = _: { };
        };
        emitClassStub = {
          "emit-class" =
            { param, state }:
            {
              resume = null;
              state = state // {
                emitCount = (state.emitCount or 0) + 1;
              };
            };
        };
        comp = fx.send "emit-classes" {
          inherit aspect;
          classKeys = [
            "nixos"
            "home"
          ];
          identity = "multi";
        };
        result = fx.handle {
          handlers = handlers.emitClassesHandler // emitClassStub;
          state = { };
        } comp;
      in
      {
        expr = result.state.emitCount;
        expected = 2;
      }
    );

    # resolve-children: emits resolve-complete with resolved aspect.
    test-resolve-children-emits-complete = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "parent";
          meta = { };
          includes = [ ];
        };
        resolveCompleteStub = {
          "resolve-complete" =
            { param, state }:
            {
              resume = null;
              state = state // {
                completed = true;
                completedName = param.name;
              };
            };
        };
        comp = fx.send "resolve-children" {
          inherit aspect;
          isMeaningful = false;
          chainIdentity = "parent";
        };
        result = fx.handle {
          handlers = handlers.resolveChildrenHandler // resolveCompleteStub;
          state = { };
        } comp;
      in
      {
        expr = {
          completed = result.state.completed;
          name = result.state.completedName;
        };
        expected = {
          completed = true;
          name = "parent";
        };
      }
    );

    # resolve-children: meaningful aspect triggers chain-push and chain-pop.
    test-resolve-children-chain-tracking = denTest (
      { den, ... }:
      let
        fx = den.lib.fx;
        handlers = den.lib.aspects.fx.handlers;
        aspect = {
          name = "meaningful";
          meta = { };
          includes = [ ];
        };
        stubs = {
          "chain-push" =
            { param, state }:
            {
              resume = null;
              state = state // {
                pushCount = (state.pushCount or 0) + 1;
              };
            };
          "chain-pop" =
            { param, state }:
            {
              resume = null;
              state = state // {
                popCount = (state.popCount or 0) + 1;
              };
            };
          "resolve-complete" =
            { param, state }:
            {
              resume = null;
              inherit state;
            };
        };
        comp = fx.send "resolve-children" {
          inherit aspect;
          isMeaningful = true;
          chainIdentity = "meaningful";
        };
        result = fx.handle {
          handlers = handlers.resolveChildrenHandler // stubs;
          state = { };
        } comp;
      in
      {
        expr = {
          pushes = result.state.pushCount;
          pops = result.state.popCount;
        };
        expected = {
          pushes = 1;
          pops = 1;
        };
      }
    );

  };
}
