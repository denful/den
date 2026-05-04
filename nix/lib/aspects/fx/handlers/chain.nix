# Effect handlers: chain-push, chain-pop
# Tracks the include ancestry chain per scope for constraint scoping.
{ lib, ... }:
let
  chainHandler = {
    "chain-push" =
      { param, state }:
      {
        resume = null;
        state = state // {
          scopedIncludesChain =
            _:
            let
              all = (state.scopedIncludesChain or (_: { })) null;
              inherit (state) currentScope;
              scopeChain = all.${currentScope} or [ ];
            in
            all
            // {
              ${currentScope} = scopeChain ++ [ param.identity ];
            };
        };
      };
    "chain-pop" =
      { param, state }:
      {
        resume = null;
        state = state // {
          scopedIncludesChain =
            _:
            let
              all = (state.scopedIncludesChain or (_: { })) null;
              inherit (state) currentScope;
              scopeChain = all.${currentScope} or [ ];
            in
            all
            // {
              ${currentScope} =
                if scopeChain == [ ] then
                  throw "fx: chain-pop on empty scopedIncludesChain"
                else
                  lib.init scopeChain;
            };
        };
      };
  };
in
{
  inherit chainHandler;
}
