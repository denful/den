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
        state = scopedAppend state "scopedIncludesChain" state.currentScope param.identity;
      };
    "chain-pop" =
      { param, state }:
      let
        all = state.scopedIncludesChain null;
        scopeChain = all.${state.currentScope} or [ ];
        updated = all // {
          ${state.currentScope} =
            if scopeChain == [ ] then
              throw "fx: chain-pop on empty scopedIncludesChain"
            else
              lib.init scopeChain;
        };
      in
      {
        resume = null;
        state = state // {
          scopedIncludesChain = _: updated;
        };
      };
  };
in
{
  inherit chainHandler;
}
