# Typed policy effect constructors.
# Policies return lists of these; the pipeline dispatches on __policyEffect.
{ ... }:
{
  # Create a new context scope (fan-out). Each resolve creates a parallel
  # branch — a sibling context with new bindings merged into parent.
  # policy.resolve {} (empty bindings) is a no-op.
  # policy.resolve.shared {} sets __shared = true for shared (non-isolated) fan-out.
  resolve =
    let
      mkResolve = shared: bindings: {
        __policyEffect = "resolve";
        __shared = shared;
        value = bindings;
        includes = [ ];
      };
      mkResolveWith = shared: includes: bindings: {
        __policyEffect = "resolve";
        __shared = shared;
        value = bindings;
        inherit includes;
      };
      mkResolveTo = shared: kind: bindings: {
        __policyEffect = "resolve";
        __shared = shared;
        __targetKind = kind;
        value = bindings;
        includes = [ ];
      };
      mkResolveToWith = shared: kind: includes: bindings: {
        __policyEffect = "resolve";
        __shared = shared;
        __targetKind = kind;
        value = bindings;
        inherit includes;
      };
    in
    {
      __functor = _: mkResolve false;
      withIncludes = mkResolveWith false;
      shared = {
        __functor = _: mkResolve true;
        # resolve.shared.to "kind" { bindings } — shared fan-out with explicit target.
        to = mkResolveTo true;
        withIncludes = mkResolveWith true;
      };
      # resolve.to "kind" { bindings } — explicit target kind for routing.
      to = {
        __functor = _: mkResolveTo false;
        withIncludes = mkResolveToWith false;
      };
    };

  # Inject an aspect into the current resolution context.
  # Accepts aspect references and inline attrsets (coerced to anonymous aspects).
  include = aspect: {
    __policyEffect = "include";
    value = aspect;
  };

  # Remove/gate an aspect from the current resolution tree.
  # Context-matched: applies to all contexts matching the policy's signature.
  exclude = aspect: {
    __policyEffect = "exclude";
    value = aspect;
  };

  # Route class or quirk content from one scope partition into a target class.
  # Tier 1 delivery — replaces den.batteries.forward for the common case.
  route = spec: {
    __policyEffect = "route";
    value = spec;
  };

  # Request post-pipeline instantiation of an entity's class content.
  # The entity carries instantiate, intoAttr, mainModule metadata.
  instantiate = spec: {
    __policyEffect = "instantiate";
    value = spec;
  };

  # Deliver a new module directly into a target class.
  # Unlike route (which moves existing pipeline content), provide injects
  # new content that didn't come from the pipeline walk.
  # spec: { class, module, path? }
  provide = spec: {
    __policyEffect = "provide";
    value = spec;
  };

  # Pipe transform builder — policies use pipe.from to attach transform
  # stages (filter, transform, fold, append, for) to a named pipe.
  pipe = {
    from = pipeNameOrRef: stages: {
      __policyEffect = "pipe";
      value = {
        pipeName = if builtins.isAttrs pipeNameOrRef then pipeNameOrRef.name else pipeNameOrRef;
        inherit stages;
      };
    };
    filter = pred: {
      __pipeStage = "filter";
      fn = pred;
    };
    transform = fn: {
      __pipeStage = "transform";
      inherit fn;
    };
    fold = fn: init: {
      __pipeStage = "fold";
      inherit fn init;
    };
    append = value: {
      __pipeStage = "append";
      inherit value;
    };
    for = fn: {
      __pipeStage = "for";
      inherit fn;
    };
    withProvenance = {
      __pipeStage = "withProvenance";
    };
    to = aspects: {
      __pipeStage = "to";
      inherit aspects;
    };
    as = targetPipeName: {
      __pipeStage = "as";
      inherit targetPipeName;
    };
    expose = {
      __pipeStage = "expose";
    };
    collect = pred: {
      __pipeStage = "collect";
      fn = pred;
    };
  };

  # Tag a value with collisionPolicy = "class-wins".
  # When the value reaches a class module that also receives the same arg
  # from the module system (e.g., NixOS provides `lib`), the class value
  # wins silently — no collision error.
  pipelineOnly =
    value:
    assert builtins.isFunction value || builtins.isAttrs value;
    if builtins.isAttrs value then
      value // { collisionPolicy = "class-wins"; }
    else
      {
        __functor = _: value;
        collisionPolicy = "class-wins";
      };

  # Wrap a policy (or list of policies) to only fire for specific entities.
  # Accepts a single entity or a list of entities as the first argument.
  # Uses id_hash for robust identity matching.
  for =
    entityOrEntities: policiesOrSingle:
    let
      entities = if builtins.isList entityOrEntities then entityOrEntities else [ entityOrEntities ];
      entityHashes = builtins.filter (h: h != null) (map (e: e.id_hash or null) entities);
      policies = if builtins.isList policiesOrSingle then policiesOrSingle else [ policiesOrSingle ];
      wrap =
        p:
        let
          inner =
            if p.__isPolicy or false then
              p
            else
              {
                __isPolicy = true;
                name = "<inline>";
                fn = p;
              };
        in
        {
          __isPolicy = true;
          inherit (inner) name;
          fn =
            ctx:
            let
              entityKind = ctx.__entityKind or null;
              ctxEntity = if entityKind != null then ctx.${entityKind} or null else null;
              ctxHash = if ctxEntity != null then ctxEntity.id_hash or null else null;
            in
            if ctxHash != null && builtins.elem ctxHash entityHashes then inner.fn ctx else [ ];
        };
    in
    if builtins.isList policiesOrSingle then map wrap policies else wrap policiesOrSingle;

  # Wrap a policy (or list of policies) to only fire when predicate is true.
  when =
    predicate: policiesOrSingle:
    let
      policies = if builtins.isList policiesOrSingle then policiesOrSingle else [ policiesOrSingle ];
      wrap =
        p:
        let
          inner =
            if p.__isPolicy or false then
              p
            else
              {
                __isPolicy = true;
                name = "<inline>";
                fn = p;
              };
        in
        {
          __isPolicy = true;
          inherit (inner) name;
          fn = ctx: if predicate ctx then inner.fn ctx else [ ];
        };
    in
    if builtins.isList policiesOrSingle then map wrap policies else wrap policiesOrSingle;

  # Create a named policy record for use in includes.
  # Usage: den.default.includes = [ (den.lib.policy.mkPolicy "host-guards" myPolicyFn) ];
  mkPolicy = name: fn: {
    __isPolicy = true;
    inherit name fn;
  };
}
