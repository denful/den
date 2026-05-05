# Effect handler: compile-parametric
# Gates, binds, tags, re-resolves parametric aspects via the resolve effect (re-entry).
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx.aspect)
    mkParametricBase
    mkParametricNext
    tagParametricResult
    prepareParametricFn
    maxParametricDepth
    ;
in
{
  compileParametricHandler = {
    "compile-parametric" =
      { param, state }:
      let
        aspect = param.aspect;
        depth = aspect.__parametricDepth or 0;
      in
      {
        resume =
          if depth >= maxParametricDepth then
            throw "den: parametric resolution exceeded ${toString maxParametricDepth} levels for '${aspect.name or "<anon>"}'"
          else
            # Step 1: gate check (dedup + constraint)
            fx.bind
              (fx.send "gate" {
                inherit aspect;
                inherit (param) identity ctx;
              })
              (
                gateResult:
                if gateResult ? blocked then
                  fx.pure gateResult.result
                else
                  let
                    # Tag constraint owner if present
                    tagged =
                      if (gateResult ? owner) && gateResult.owner != null then
                        aspect
                        // {
                          meta = (aspect.meta or { }) // {
                            constraintOwner = gateResult.owner;
                          };
                        }
                      else
                        aspect;

                    # compileFn: prepareParametricFn → bind → base → next → tag
                    compileFn =
                      a:
                      fx.bind (prepareParametricFn a) (
                        resolved:
                        let
                          base = mkParametricBase a resolved;
                          next = mkParametricNext a base resolved;
                          result = tagParametricResult a next // {
                            __parametricDepth = (a.__parametricDepth or 0) + 1;
                          };
                        in
                        fx.pure result
                      );
                  in
                  # Step 2: bind (probes scope handlers, calls compileFn or defers)
                  fx.bind
                    (fx.send "bind" {
                      aspect = tagged;
                      inherit compileFn;
                    })
                    (
                      bindResult:
                      if bindResult ? value then
                        # Re-enter resolution with the compiled result
                        fx.send "resolve" {
                          aspect = bindResult.value;
                          inherit (param) identity ctx;
                        }
                      else
                        # Deferred — no resolution possible
                        fx.pure [ ]
                    )
              );
        inherit state;
      };
  };
}
