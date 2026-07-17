# Effect handler: compile
# Shape router — dispatches to compile-* based on aspect shape.
{
  den,
  lib,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) argClass;
  inherit (den.lib.aspects.fx.contentUtil) unwrapContentValuesList;
  inherit (den.lib.schemaUtil) schemaEntityKindsSet;
  schema = den.schema or { };
  classReg = den.classes or { };

  # Entity kinds NAMED as function args by a static aspect's class-content
  # modules, unioned across every class key. Mirrors emit-classes.nix
  # `namedEntityArgs` (bare-fn modules only) but does NOT gate on ctx — the
  # router decides fan-out eligibility via the schema DAG (see below).
  namedClassEntityKinds =
    aspect:
    let
      classKeys = builtins.filter (k: classReg ? ${k}) (builtins.attrNames aspect);
      kindsIn =
        module:
        if builtins.isFunction module then
          builtins.filter (a: schemaEntityKindsSet ? ${a}) (builtins.attrNames (builtins.functionArgs module))
        else
          [ ];
    in
    lib.unique (
      builtins.concatMap (k: builtins.concatMap kindsIn (unwrapContentValuesList aspect.${k})) classKeys
    );
in
{
  compileHandler = {
    "compile" =
      { param, state }:
      let
        aspect = param.aspect;
        meta = aspect.meta or { };
        isStatic =
          !(meta ? __forward) && !(meta ? guard) && !(aspect ? __fn) && (aspect.__args or { }) == { };

        # A class-content module naming a strict DESCENDANT of the emitting scope's
        # kind (host-scope aspect with `nixos = { user, ... }:`) has no such binding
        # in scope, so wrapClassModule would drop it silently. Promote the aspect to
        # be parametric on those kinds: the bind handler then fans it per descendant
        # instance via the SAME machinery the aspect-level `{ user, ... }:` form uses,
        # making the two forms equivalent. Descendant classification (not mere
        # ctx-absence) keeps scope-kind-self and ancestor args on the static path —
        # bind would only satisfy or inert those. `__parametricResolvedArgs` excludes
        # kinds already bound by an earlier fan, so the re-resolved body (still naming
        # the kind) does not re-promote into a loop.
        scopeKind = ((state.scopeEntityKind or (_: { })) null).${state.currentScope or ""} or null;
        resolvedArgs = aspect.__parametricResolvedArgs or [ ];
        promoteKinds =
          if isStatic && scopeKind != null then
            builtins.filter (
              k: (argClass.isDescendantOf schema scopeKind k) && !(builtins.elem k resolvedArgs)
            ) (namedClassEntityKinds aspect)
          else
            [ ];
        promoted =
          if promoteKinds != [ ] then
            aspect
            // {
              __fn = _: aspect;
              __args = lib.genAttrs promoteKinds (_: false);
              __functor = self: self.__fn;
            }
          else
            aspect;

        effect =
          if meta ? __forward then
            "compile-forward"
          else if meta ? guard then
            "compile-conditional"
          else if promoted ? __fn || (promoted.__args or { }) != { } then
            "compile-parametric"
          else
            "compile-static";
      in
      {
        resume = fx.send effect (param // { aspect = promoted; });
        inherit state;
      };
  };
}
