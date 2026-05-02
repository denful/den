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
      scopeHandlers = constantHandler ctx;
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
      schemaIncludes = ((den.schema or { }).${name} or { }).includes or [ ];
    in
    {
      inherit name;
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
