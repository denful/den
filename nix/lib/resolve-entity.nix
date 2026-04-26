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
  schemaKinds = builtins.attrNames (den.schema or { });
  aspectKinds = builtins.filter (
    k: k != "conf" && !(lib.hasPrefix "_" k) && k != "default"
  ) schemaKinds;
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
      # Host-level framework aspects have no inbound policy — deliver directly.
      hostFramework =
        if name == "host" then
          builtins.filter (x: x != null) [ (den.aspects.os-host-fwd or null) ]
        else
          [ ];
      entityIncludes = den.entityIncludes.${name} or [ ];
      entityProvides = den.entityProvides.${name} or { };
    in
    {
      inherit name;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into = null;
      };
      rootIncludes = selfProvide ++ hostFramework ++ entityIncludes;
      provides = entityProvides;
      includes = [ ];
      __ctxStage = name;
      __scopeHandlers = scopeHandlers;
    };
in
resolveEntity
