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
      # Capture schema-level collisionPolicy eagerly — avoids circular eval
      # when read during post-pipeline wrapping (wrapClassModule).
      collisionPolicy = schemaEntry.collisionPolicy or null;
      # Store collisionPolicy as a separate __collisionPolicies entry in ctx
      # so wrapClassModule can read it without accessing the live entity config.
      augmentedCtx =
        ctx
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
              __fn = c: c.${name}.aspect;
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
      inherit name collisionPolicy;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
      };
      includes = selfProvide ++ schemaIncludes;
      __entityKind = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
