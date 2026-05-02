# Handler for policy.provide — collects provided modules for post-pipeline delivery.
{
  lib,
  den,
  ...
}:
let
  provideHandler = {
    "register-provide" =
      { param, state }:
      let
        scope = state.currentScope;
        all = state.scopedProvides null;
      in
      {
        resume = null;
        state = state // {
          scopedProvides =
            _:
            all
            // {
              ${scope} = (all.${scope} or [ ]) ++ [ (param // { sourceScopeId = scope; }) ];
            };
        };
      };
  };
in
{
  inherit provideHandler;
}
