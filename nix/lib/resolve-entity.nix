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
        provider = [ ];
      };
      excludes = schemaExcludes;
      includes = selfProvide ++ schemaIncludes;
      __entityKind = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
