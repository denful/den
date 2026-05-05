# Policy type — wraps raw functions into { __isPolicy, name, fn } records.
{ lib }:
let
  policyFnType = lib.types.mkOptionType {
    name = "policyFunction";
    description = "policy function (context -> effects list)";
    check = v: lib.isFunction v || (builtins.isAttrs v && v.__isPolicy or false);
    merge =
      loc: defs:
      let
        name = lib.last loc;
        lastDef = lib.last defs;
        raw = lastDef.value;
      in
      if builtins.isAttrs raw && raw.__isPolicy or false then
        raw // { inherit name; }
      else if lib.isFunction raw then
        {
          __isPolicy = true;
          inherit name;
          fn = raw;
        }
      else
        throw "den.policies.${name}: expected a function, got ${builtins.typeOf raw}";
  };
in
{
  policyRegistryType = lib.types.lazyAttrsOf policyFnType;
}
