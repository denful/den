# Effect handlers: chain-push, chain-pop
# Tracks the include ancestry chain per scope for constraint scoping.
{ lib, ... }:
let
  inherit (import ./state-util.nix) scopedAppend;

  chainHandler = {
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
