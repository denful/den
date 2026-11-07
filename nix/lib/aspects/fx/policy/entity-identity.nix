# Entity identity (#694 §11a R1, #752): by id_hash when both records carry
# one, else by value. A comparison den cannot decide is an error, never a quiet
# mismatch: two same-named records only one of which carries an id_hash, or
# two records that differ only in function values.
{ lib }:
let
  describeRecord =
    r: "${r.name or "<unnamed>"}${lib.optionalString (r ? id_hash) " (id_hash ${r.id_hash})"}";

  # A binding is matched to an entity scope by id_hash, or by value when
  # neither record has one. A record with an id_hash and one without are
  # different entities, unless they share a name: then den cannot tell, and a
  # quiet mismatch would silently fire none of the entity's rules.
  mixedIdHash =
    kind: a: others:
    let
      clash = lib.findFirst (b: (b.name or null) != null && b.name == (a.name or null)) null others;
    in
    if clash == null then
      [ ]
    else
      throw "den: two `${kind}` records, ${describeRecord a} and ${describeRecord clash}, share a name but only one carries an id_hash, so den cannot tell whether they are one entity; give both an id_hash, or neither";

  # "eq", "ne", or "fn" when the values differ only in function-valued
  # attributes, which Nix compares unequal unless they are the same value.
  valueDiff =
    a: b:
    if a == b then
      "eq"
    else if builtins.isFunction a && builtins.isFunction b then
      "fn"
    else if builtins.isAttrs a && builtins.isAttrs b then
      let
        names = builtins.attrNames a;
        isLeaf = n: !(builtins.isAttrs a.${n}) && !(builtins.isFunction a.${n});
      in
      if names != builtins.attrNames b then
        "ne"
      else if builtins.any (n: isLeaf n && a.${n} != b.${n}) names then
        "ne"
      else
        let
          diffs = map (n: valueDiff a.${n} b.${n}) (builtins.filter (n: !isLeaf n) names);
        in
        if builtins.elem "ne" diffs then
          "ne"
        else if builtins.elem "fn" diffs then
          "fn"
        else
          "eq"
    else
      "ne";

  # Pipeline products (`hasAspect`, `__`-prefixed internals such as
  # `__resolveResult`) are not identity, and forcing them would resolve the
  # entity again; names are compared first, so most mismatches stop there.
  identityAttrs =
    r:
    builtins.removeAttrs r (
      [ "hasAspect" ] ++ builtins.filter (lib.hasPrefix "__") (builtins.attrNames r)
    );
  sameByValue =
    kind: a: b:
    let
      d = valueDiff (identityAttrs a) (identityAttrs b);
    in
    if (a.name or null) != (b.name or null) then
      false
    else if d == "fn" then
      throw "den: two `${kind}` records named ${a.name or "<unnamed>"} differ only in function values, so den cannot tell whether they are one entity; give them an id_hash"
    else
      d == "eq";

  # A record with an id_hash and one without are different entities, unless
  # they share a name.
  sameEntity =
    kind: a: b:
    if a ? id_hash && b ? id_hash then
      a.id_hash == b.id_hash
    else if a ? id_hash then
      builtins.seq (mixedIdHash kind a [ b ]) false
    else if b ? id_hash then
      builtins.seq (mixedIdHash kind b [ a ]) false
    else
      sameByValue kind a b;
in
{
  inherit
    describeRecord
    mixedIdHash
    valueDiff
    sameByValue
    sameEntity
    ;
}
