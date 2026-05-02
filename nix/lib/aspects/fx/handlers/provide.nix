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
        spec = param // {
          sourceScopeId = param.sourceScopeId or scope;
        };
        # Dedup key: same provide registered from multiple policy dispatch levels.
        provideKey = "${spec.class}/${lib.concatStringsSep "/" (spec.path or [ ])}";
        registeredProvides = (state.registeredProvideKeys or (_: { })) null;
        alreadyRegistered = registeredProvides ? ${provideKey};
      in
      {
        resume = null;
        state =
          if alreadyRegistered then
            state
          else
            state
            // {
              scopedProvides =
                _:
                let
                  all = state.scopedProvides null;
                in
                all
                // {
                  ${scope} = (all.${scope} or [ ]) ++ [ spec ];
                };
              registeredProvideKeys = _: registeredProvides // { ${provideKey} = true; };
            };
      };
  };
in
{
  inherit provideHandler;
}
