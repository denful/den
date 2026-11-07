{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # Entity kinds that carry .aspect on their schema entry.
  # These get a parametric self-provide wrapper so the root aspect
  # is resolved once the entity's scope handlers are established.
  inherit (den.lib.schemaUtil) schemaEntityKinds;
  # Filter "default" — handled specially at line 23.
  aspectKinds = builtins.filter (k: k != "default") schemaEntityKinds;
  aspectKindSet = lib.genAttrs aspectKinds (_: true);

  resolveEntity =
    name: ctx:
    let
      schemaEntry = (den.schema or { }).${name} or { };
      schemaIncludes = schemaEntry.includes or [ ];
      schemaExcludes = schemaEntry.excludes or [ ];
      # Capture schema-level collisionPolicy eagerly — avoids circular eval
      # when read during post-pipeline wrapping (wrapClassModule).
      collisionPolicy = schemaEntry.collisionPolicy or null;
      # For entity kinds that carry related entity bindings on their schema
      # entry (e.g. home.host, home.user), include those bindings in the
      # context.  This mirrors config.resolved in options.nix which reads
      # _module.args for entity-kind keys.
      entity = ctx.${name} or null;
      # The instance's own collections (`den.hosts.<sys>.<n>.includes`, and the
      # same key on any other entity kind). Read here rather than per entity
      # kind so every kind declaring `isEntity` honours the key at once, and
      # read at all because the instance type is built with `strict = false`:
      # its freeform type absorbed the key instead of raising "option does not
      # exist", so it was accepted and dropped in silence (#663). `includes` is
      # the activation key at the aspect, schema and default tiers, which is
      # what makes the instance spelling the natural guess.
      #
      # Last in the include order, after the schema tier: an instance is the
      # most specific site an entity's content can be written at, so its
      # definitions merge over what its kind's schema supplies.
      instanceCollection =
        key: if entity == null || !builtins.isAttrs entity then [ ] else entity.${key} or [ ];
      entityDerivedBindings =
        if entity == null || !builtins.isAttrs entity then
          { }
        else
          lib.filterAttrs (
            k: v:
            k != name && builtins.elem k schemaEntityKinds && v != null && builtins.isAttrs v && !(ctx ? ${k})
          ) (lib.intersectAttrs (lib.genAttrs schemaEntityKinds (_: null)) entity);
      augmentedCtx =
        ctx
        // entityDerivedBindings
        // lib.optionalAttrs (collisionPolicy != null) {
          __collisionPolicies = (ctx.__collisionPolicies or { }) // {
            ${name} = collisionPolicy;
          };
        };
      scopeHandlers = constantHandler augmentedCtx;
      # #694's transition defaults reach host, user and home through
      # den.default; any other kind whose entity carries a class (a guest that
      # is its own host) gets them here, so nothing changes for it either
      # until den.lib.migrations.removalDate.
      transitionDefaults =
        lib.optionals
          (
            den.lib.migrations.transitionActive
            && !(builtins.elem name [
              "host"
              "user"
              "home"
            ])
            && builtins.isAttrs entity
            && entity ? class
          )
          (
            map (b: b.__defaultForm) [
              den.batteries.user-aspects
              den.batteries.mutual-provider
            ]
          );
      selfProvide =
        if name == "default" && den ? default then
          [ den.default ]
        else if aspectKindSet ? ${name} then
          [
            {
              __fn = c: c.${name}.aspect or { };
              __args = {
                ${name} = false;
              };
              name = "<self:${name}>";
              meta = { };
              includes = [ ];
            }
          ]
        else
          [ ];
    in
    {
      inherit name;
      meta = {
        handleWith = null;
        aspect-chain = [ ];
      };
      excludes = schemaExcludes ++ instanceCollection "excludes";
      includes = selfProvide ++ schemaIncludes ++ transitionDefaults ++ instanceCollection "includes";
      __entityKind = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
