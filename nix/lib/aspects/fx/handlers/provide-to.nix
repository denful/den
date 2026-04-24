# Handler for cross-entity provide-to data collection.
# Aspects declare provide-to.${label} = data; this handler accumulates
# emissions in state.provideTo (thunk-wrapped) for phase 2 distribution.
{ ... }:
{
  provideToHandler = {
    "provide-to" =
      { param, state }:
      {
        resume = null;
        state = state // {
          provideTo = _: ((state.provideTo or (_: [ ])) null) ++ [ param ];
        };
      };
  };
}
