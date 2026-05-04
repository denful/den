{ den, ... }:
let
  inherit (den.lib.aspects.fx.aspect) emitIncludes;

  includeHandler = {
    # Unregister a dedupKey from includeSeen (used when exclude fires after eager registration).
    "include-unseen" =
      { param, state }:
      let
        key = param;
        seen = (state.includeSeen or (_: { })) null;
      in
      {
        resume = null;
        state = state // {
          includeSeen = _: builtins.removeAttrs seen [ key ];
        };
      };

    # Thin wrapper: wraps raw child as single-element list and delegates
    # to emitIncludes which handles wrapping, classification, and dispatch.
    "emit-include" =
      { param, state }:
      let
        rawChild = param.child or param;
        parentScopeHandlers = param.__parentScopeHandlers or null;
        parentCtxId = param.__parentCtxId or null;
      in
      {
        resume = emitIncludes {
          __parentScopeHandlers = parentScopeHandlers;
          __parentCtxId = parentCtxId;
          __skipNameAnon = true;
        } [ rawChild ];
        inherit state;
      };
  };

in
{
  inherit includeHandler;
}
