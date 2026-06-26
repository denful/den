# Typed policy effect constructors.
# Policies return lists of these; the pipeline dispatches on __policyEffect.
{ lib, ... }:
let
  # Coerce a value into an inner policy record for use in `for` / `when`.
  # Accepts: policies (__isPolicy), effect descriptors (__policyEffect),
  # inline aspect attrsets, or raw functions (ctx -> [effects]).
  toInnerPolicy =
    p:
    if p.__isPolicy or false then
      p
    else if p.__policyEffect or null != null then
      {
        __isPolicy = true;
        name = "<effect:${p.__policyEffect}>";
        fn = _: [ p ];
      }
    else if builtins.isAttrs p then
      {
        __isPolicy = true;
        name = "<inline-aspect>";
        fn = _: [
          {
            __policyEffect = "include";
            value = p;
          }
        ];
      }
    else
      {
        __isPolicy = true;
        name = "<inline>";
        fn = p;
      };

  # ===== deliver — the user-facing delivery-edge constructor ============
  # `deliver` is the public primitive over the edge layer (spec §4): it declares
  # ONE delivery edge `(S, T, P, M)` and nothing else. `route` and `provides`
  # (the attrset entries below) are PERMANENT shims that desugar onto it, so
  # `deliver` lives in this `let` block where both can reference it.
  #
  #   deliver {
  #     from;            # the source S:
  #                      #   - a class name (string)  → collect that class's bucket
  #                      #     and move it (the route case);
  #                      #   - { module = <mod>; }      → inject a NEW module that
  #                      #     did not come from the walk (the provides case).
  #     to;              # target class T (the instantiation-root class).
  #     at ? [ ];        # attrpath P inside T's config ([] = merge at root).
  #     mode ? "merge";  # M, explicit and exhaustive: "merge" | "nest" | "verbatim".
  #     guard ? null;    # optional conditional gate (class-source only).
  #     adaptArgs ? null;# optional specialArgs adapter (class-source only).
  #   }
  #
  # Surface rules (spec §4, binding):
  #   - `mode = "verbatim"` is EXPLICIT — there is no `reinstantiate` flag on
  #     `deliver` and no isolation-derived verbatim magic (rejected by the spec).
  #     The `route` shim maps its legacy `reinstantiate = true` to `mode =
  #     "verbatim"` so existing users keep working without touching `deliver`.
  #   - `appendToParent` is NOT accepted here — `to` already names the target;
  #     parent-targeting is constructor-internal (T = parent root, fixed at
  #     construction) and reachable only through the `route` shim for compat.
  #
  # `deliver` produces the same effect descriptor the edge constructors already
  # consume (`route` / `provide`), so the materializer never learns a new
  # mechanism name (spec §2 invariant). Shims thread their mechanism-only fields
  # through the internal `__extra` escape hatch — never part of the user surface.
  deliver =
    {
      from,
      to,
      at ? [ ],
      mode ? "merge",
      guard ? null,
      adaptArgs ? null,
      __extra ? { },
    }:
    let
      validModes = {
        merge = true;
        nest = true;
        verbatim = true;
      };
      isModuleSource = builtins.isAttrs from && from ? module;
    in
    if !(validModes ? ${mode}) then
      throw "den: deliver: mode must be one of merge|nest|verbatim, got '${toString mode}'"
    else if isModuleSource then
      # Module source S = the provided module — a `provide` edge (nest ∘ merge,
      # §B Decision 1). `verbatim` is meaningless for injected content (there is
      # no collected wrapper to keep by reference) — reject it explicitly.
      if mode == "verbatim" then
        throw "den: deliver: mode \"verbatim\" applies to class sources (collected modules), not module sources"
      else
        {
          __policyEffect = "provide";
          value = {
            class = to;
            inherit (from) module;
            path = at;
          }
          // __extra;
        }
    else
      # Class source S = collected(from) — a `route` edge. mode → reinstantiate
      # (verbatim) is the ONLY mode→flag translation; nest/merge are derived by
      # the route classifier from path, matching the legacy route shape.
      {
        __policyEffect = "route";
        value = {
          fromClass = from;
          intoClass = to;
          path = at;
          reinstantiate = mode == "verbatim";
        }
        // lib.optionalAttrs (guard != null) { inherit guard; }
        // lib.optionalAttrs (adaptArgs != null) { inherit adaptArgs; }
        // __extra;
      };
in
{
  inherit deliver;

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
  #
  # SHIM over `deliver` (spec §4): `route` is PERMANENT user-API sugar and may
  # live on indefinitely. It desugars its full legacy signature onto a single
  # `deliver` edge: `fromClass`→`from`, `intoClass`→`to`, `path`/`intoPath`→`at`,
  # and `reinstantiate = true`→`mode = "verbatim"`. The mechanism-only fields
  # (`collectSubtree`, `appendToParent`, `instantiate`, `adapterKey`,
  # `adapterModule`, …) are route-internal and ride through `deliver`'s `__extra`
  # escape hatch — they are NOT part of the `deliver` surface.
  #
  # TODO: add deprecation warning before any future removal.
  #
  # `intoPath` is the public target-path name — it pairs with `intoClass` and
  # `fromClass`, matching the forward API. `path` is kept as a back-compat
  # alias; both normalize to the internal `path` key the route handler reads.
  # Passing an unsupported key (e.g. `intoPath` before this aliasing existed)
  # used to be silently dropped, landing content at the class root.
  route =
    spec:
    let
      path = spec.intoPath or spec.path or [ ];
      reinstantiate = spec.reinstantiate or false;
      # Everything that is not a clean `deliver` field is a route-internal
      # mechanism field threaded verbatim through __extra.
      extra = builtins.removeAttrs spec [
        "fromClass"
        "intoClass"
        "intoPath"
        "path"
        "reinstantiate"
        "guard"
        "adaptArgs"
      ];
    in
    if (spec ? intoPath) && (spec ? path) then
      throw "den: policy.route: pass either `intoPath` or `path`, not both"
    else
      deliver {
        from = spec.fromClass or "?";
        to = spec.intoClass or "?";
        at = path;
        mode =
          if reinstantiate then
            "verbatim"
          else if path == [ ] then
            "merge"
          else
            "nest";
        guard = spec.guard or null;
        adaptArgs = spec.adaptArgs or null;
        __extra = extra;
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
  #
  # SHIM over `deliver` (spec §4): `provide` is PERMANENT user-API sugar. It
  # desugars onto a module-source `deliver` edge: `class`→`to`, `module`→
  # `from.module`, `path`→`at` (P=[] degenerates to a plain merge contribution,
  # P≠[] is the `nest ∘ merge` decomposition). Any extra spec fields ride
  # through `__extra`.
  #
  # TODO: add deprecation warning before any future removal.
  provide =
    spec:
    let
      extra = builtins.removeAttrs spec [
        "class"
        "module"
        "path"
      ];
    in
    deliver {
      from = {
        inherit (spec) module;
      };
      to = spec.class;
      at = spec.path or [ ];
      mode = if (spec.path or [ ]) == [ ] then "merge" else "nest";
      __extra = extra;
    };

  # Request a deferred node spawn. Records a marker resolved post-walk
  # over the parent pipeline's full scope-tree state (host + siblings), so the
  # projected home content sees fleet-wide pipe values. `classes` defaults to
  # the user's classes (or homeManager) at the drain site when null.
  spawn =
    {
      classes ? null,
    }:
    {
      __policyEffect = "spawn";
      value = {
        inherit classes;
      };
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
    broadcast = pred: {
      __pipeStage = "broadcast";
      fn = pred;
    };
    collect = pred: {
      __pipeStage = "collect";
      fn = pred;
    };
    collectAll = pred: {
      __pipeStage = "collectAll";
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
          inner = toInnerPolicy p;
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
  # When wrapping inline aspects or effect descriptors, emits a conditional
  # aspect (meta.guard) instead of a policy. This avoids the cycle where
  # predicates that access entity.hasAspect trigger config.resolved during
  # policy dispatch. The compile-conditional handler provides hasAspect from
  # the in-flight pathSet, plus entity-shaped stubs for destructuring.
  when =
    predicate: policiesOrSingle:
    let
      policies = if builtins.isList policiesOrSingle then policiesOrSingle else [ policiesOrSingle ];
      # Wrap a non-policy value as a conditional aspect (compile-conditional path).
      wrapAsConditional =
        p:
        let
          effectType = p.__policyEffect or null;
          aspects =
            if effectType == "include" then
              [ p.value ]
            else if effectType != null then
              throw "den: policy.when does not support ${effectType} effect descriptors — only include and inline aspects"
            else
              [ p ];
        in
        {
          name = "<when>";
          meta.guard = predicate;
          meta.aspects = aspects;
          includes = [ ];
        };
      # Wrap a policy value with predicate gating (dispatch path).
      # Pre-check the predicate's required args against ctx so the wrapper
      # does not fire in contexts that would crash the predicate's
      # destructuring pattern (e.g. { host, ... } in a home-only scope).
      predicateArgs = if builtins.isFunction predicate then builtins.functionArgs predicate else { };
      predicateRequiredArgs = builtins.filter (k: !predicateArgs.${k}) (builtins.attrNames predicateArgs);
      wrapAsPolicy =
        p:
        let
          inner = toInnerPolicy p;
        in
        {
          __isPolicy = true;
          inherit (inner) name;
          fn =
            ctx:
            if builtins.all (k: ctx ? ${k}) predicateRequiredArgs && predicate ctx then inner.fn ctx else [ ];
        };
      wrap =
        p: if p.__isPolicy or false || builtins.isFunction p then wrapAsPolicy p else wrapAsConditional p;
    in
    if builtins.isList policiesOrSingle then map wrap policies else wrap policiesOrSingle;

  # Create a named policy record for use in includes.
  # Usage: den.default.includes = [ (den.lib.policy.mkPolicy "host-guards" myPolicyFn) ];
  mkPolicy = name: fn: {
    __isPolicy = true;
    inherit name fn;
  };
}
