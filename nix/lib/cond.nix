# `den.lib.cond`: conditions over facts, for `den.users.<n>.hosts`. The terms
# are gen-algebra's; den re-exports only the formers a membership test needs.
{ den, lib, ... }:
let
  inherit (den.lib.schema) gen;
  algebra = gen.algebra.term gen.identity.hashIdentity;
  inherit (algebra) term;

  # Every `eq` path in `t`, so each is checked against the declared facts.
  paths =
    t:
    let
      f = t.__bodyTerm or null;
    in
    if algebra.isRefusal t then
      [ ]
    else if f == "Eq" then
      [ t.path ]
    else if f == "Not" then
      paths t.operand
    else if f == "All" || f == "Any" then
      lib.concatMap paths t.items
    else
      [ ];
in
{
  inherit (term)
    eq
    all
    any
    not
    always
    ;

  # A whole `hosts` entry naming `den.predicates.<name>`.
  predicate =
    name:
    if builtins.isString name then
      { __denPredicate = name; }
    else
      throw "den: den.lib.cond.predicate takes a predicate name, got a ${builtins.typeOf name}.";

  isCondition = algebra.isTerm;
  inherit (algebra) isRefusal;
  isPredicate = v: builtins.isAttrs v && v ? __denPredicate;

  # Decides `t` over `context` (`{ host = …; user = …; }`). A refusal is an
  # error, never a non-match.
  decide =
    what: context: t:
    let
      r = algebra.resolveTerm {
        inherit context;
        declared = builtins.attrNames context;
      } t;
    in
    if algebra.isRefusal r then
      throw "den: ${what} is a condition den can't decide (${r.left.code}): ${
        builtins.toJSON (r.left.witness or { })
      }"
    else if !(builtins.isBool r.right) then
      throw "den: ${what} decided to a ${builtins.typeOf r.right}, not a bool."
    else
      r.right;

  inherit paths;
}
