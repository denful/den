# A battery's name from its arguments. The name is the battery's identity
# (dedup, the policy registry), so distinct arguments must give distinct
# names: arguments are rendered as JSON, which no separator choice can
# confuse (`[ "a,b" ]` is not `[ "a" "b" ]`). A list that is a set to the
# battery (users, package names) is sorted and deduplicated first, so the
# same set is the same battery.
{ lib, ... }:
{
  # setOf : [ string ] -> string
  setOf =
    xs:
    if !(builtins.isList xs) || !(builtins.all builtins.isString xs) then
      throw "den: a battery argument list must be a list of strings"
    else
      builtins.toJSON (lib.unique (lib.sort builtins.lessThan xs));

  # pathOf : path | string -> string
  # A filesystem root as an identity. The store hash stays: two inputs both
  # stored as `source` with the same relative path are distinct roots.
  pathOf =
    root:
    lib.removePrefix "${builtins.storeDir}/" (builtins.unsafeDiscardStringContext (toString root));

  # withoutStoreHash : string -> string
  # How a message shows an identity: a `<storeDir>/<hash>-` or a `<hash>-`
  # pathOf left is dropped, so readers see `source/hosts/igloo`. Only at the
  # start of a path segment, so a name that merely contains a hash-like run
  # (`my-<run>-thing`) is shown as written.
  withoutStoreHash =
    s:
    lib.concatStrings (
      map (x: if builtins.isList x then builtins.head x else x) (
        builtins.split "(^|[(/])(${lib.escapeRegex builtins.storeDir}/)?[0-9a-df-np-sv-z]{32}-" s
      )
    );
}
