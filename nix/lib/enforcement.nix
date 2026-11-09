# Policy enforcement modes (#694 §11a O2): strict > per-policy > lenient, and
# only layers that set a value take part.
{ lib, ... }:
let
  rank = {
    lenient = 0;
    per-policy = 1;
    strict = 2;
  };
in
{
  strictest =
    vals:
    let
      set = builtins.filter (v: v != null) vals;
    in
    if set == [ ] then
      null
    else
      builtins.foldl' (a: b: if rank.${b} > rank.${a} then b else a) (builtins.head set) set;
}
