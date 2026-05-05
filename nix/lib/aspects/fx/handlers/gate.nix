# Effect handler: gate
# Dedup + constraint check as a single composite effect.
# Resumes { blocked, result } on dedup/constraint rejection,
# or { passed, owner? } on clean pass-through.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;

  gateHandler = {
    "gate" =
      { param, state }:
      let
        inherit (param) aspect;
        nodeIdentity = param.identity or (identity.key aspect);
      in
      {
        resume =
          # Step 1: dedup check
          fx.bind (fx.send "check-dedup" aspect) (
            { isDuplicate, dedupKey }:
            if isDuplicate then
              fx.pure {
                blocked = true;
                result = [ ];
              }
            else
              # Step 2: constraint check
              fx.bind
                (fx.send "check-constraint" {
                  inherit (param) identity;
                  inherit aspect;
                })
                (
                  decision:
                  if decision.action == "exclude" then
                    let
                      tombstone = identity.tombstone aspect { excludedFrom = decision.owner; };
                    in
                    fx.bind (fx.send "resolve-complete" tombstone) (
                      _:
                      if dedupKey == null then
                        fx.pure {
                          blocked = true;
                          result = [ tombstone ];
                        }
                      else
                        fx.bind (fx.send "include-unseen" dedupKey) (
                          _:
                          fx.pure {
                            blocked = true;
                            result = [ tombstone ];
                          }
                        )
                    )
                  else if decision.action == "substitute" then
                    let
                      tombstone = identity.tombstone aspect {
                        excludedFrom = decision.owner;
                        replacedBy = decision.replacement.name or "<anon>";
                      };
                    in
                    fx.bind (fx.send "resolve-complete" tombstone) (
                      _:
                      fx.bind
                        (fx.send "resolve" {
                          aspect = decision.replacement;
                          identity = identity.key decision.replacement;
                          ctx = param.ctx or { };
                        })
                        (
                          resolved:
                          let
                            replacementResult = if builtins.isList resolved then resolved else [ resolved ];
                          in
                          fx.pure {
                            blocked = true;
                            result = [ tombstone ] ++ replacementResult;
                          }
                        )
                    )
                  else
                    # pass-through
                    fx.pure (
                      {
                        passed = true;
                      }
                      // lib.optionalAttrs ((decision ? owner) && decision.owner != null) {
                        inherit (decision) owner;
                      }
                    )
                )
          );
        inherit state;
      };
  };
in
{
  inherit gateHandler;
}
