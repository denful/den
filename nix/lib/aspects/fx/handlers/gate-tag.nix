# Shared gate+tag logic for compile-static and compile-parametric.
# Performs dedup/constraint gate check and tags constraint owner on aspect.
{ fx }:
{
  # Run gate check (or skip if already gated), then tag and continue.
  gateAndTag =
    { param, aspect }:
    cont:
    let
      gateOrSkip =
        if param.gated or false then
          fx.pure { passed = true; }
        else
          fx.send "gate" {
            inherit aspect;
            inherit (param) identity ctx;
          };
    in
    fx.bind gateOrSkip (
      gateResult:
      if gateResult ? blocked then
        fx.pure gateResult.result
      else
        let
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
        in
        cont tagged
    );
}
