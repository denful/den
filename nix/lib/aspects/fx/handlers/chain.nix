# Effect handlers: chain-push, chain-pop
# Tracks the include ancestry chain per scope for constraint scoping.
{ lib, ... }:
let
  inherit (import ./state-util.nix) scopedAppend;

  chainHandler = {
    # Den's provenance (#694): the cross-provider tokens and the emitting
    # policy's registration chain a policy-emitted include is walked under.
    # Pushed only by den's include emitter (policy/apply.nix), from fields den
    # sets on the effect; read innermost-first (handlers/provenance.nix).
    "provenance-push" =
      { param, state }:
      {
        resume = null;
        state = scopedAppend state "scopedProvenanceStack" state.currentScope param;
      };
    "provenance-pop" =
      { param, state }:
      let
        all = (state.scopedProvenanceStack or (_: { })) null;
        stack = all.${state.currentScope} or [ ];
      in
      {
        resume = null;
        state = state // {
          scopedProvenanceStack =
            _:
            all
            // {
              ${state.currentScope} =
                if stack == [ ] then throw "fx: provenance-pop on an empty stack" else lib.init stack;
            };
        };
      };
    "chain-push" =
      { param, state }:
      {
        resume = null;
        # scopedIncludesChain carries the rendered string (unchanged — several
        # consumers key on it directly); scopedIncludesChainSegments carries
        # the same position as a segment list, pushed in lockstep.
        state = scopedAppend (scopedAppend state "scopedIncludesChain" state.currentScope
          param.identity
        ) "scopedIncludesChainSegments" state.currentScope (param.segments or [ ]);
      };
    "chain-pop" =
      { param, state }:
      let
        all = state.scopedIncludesChain null;
        scopeChain = all.${state.currentScope} or [ ];
        empty = scopeChain == [ ];
        updated = all // {
          ${state.currentScope} =
            if empty then throw "fx: chain-pop on empty scopedIncludesChain" else lib.init scopeChain;
        };
        allSegments = (state.scopedIncludesChainSegments or (_: { })) null;
        segmentsChain = allSegments.${state.currentScope} or [ ];
        updatedSegments = allSegments // {
          ${state.currentScope} =
            if empty then throw "fx: chain-pop on empty scopedIncludesChain" else lib.init segmentsChain;
        };
      in
      {
        resume = null;
        state = state // {
          scopedIncludesChain = _: updated;
          scopedIncludesChainSegments = _: updatedSegments;
        };
      };
  };
in
{
  inherit chainHandler;
}
