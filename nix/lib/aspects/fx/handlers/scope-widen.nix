# Handles: scope-widened
# Drains deferred includes satisfiable under the new context, re-resolves each.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
in
{
  scopeWidenHandler = {
    "scope-widened" =
      { param, state }:
      let
        ctx = param.ctx;
      in
      {
        resume = fx.bind (fx.send "drain" ctx) (
          satisfiable:
          builtins.foldl' (
            acc: deferred:
            fx.bind acc (
              _:
              fx.send "resolve" {
                aspect = deferred.child;
                identity = identity.key deferred.child;
                inherit ctx;
                gated = true;
              }
            )
          ) (fx.pure null) satisfiable
        );
        inherit state;
      };
  };
}
