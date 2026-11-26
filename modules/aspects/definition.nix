{
  lib,
  den,
  ...
}:
let
  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);
  allHomes = lib.concatMap builtins.attrValues (builtins.attrValues den.homes);

  entityDeps = map (from: {
    ${from.name} = lib.genAttrs (from.classes or [ from.class ]) (_: { });
  }) (allHosts ++ allHomes);

  # From the registry and each host's declared users, never the assigned ones:
  # `den.classes` reads every aspect, and assignment reads host `includes`,
  # which are aspects. A user only assigned to a host has the registry's
  # classes there; a declared one may add its own.
  declaredClasses = builtins.zipAttrsWith (_: lib.concatLists) (
    map (h: h.__declaredUserClasses) allHosts
  );
  userDeps = map (n: {
    ${n} = lib.genAttrs (lib.unique (den.users.${n}.classes ++ (declaredClasses.${n} or [ ]))) (_: { });
  }) (builtins.attrNames den.users);
in
{
  den.aspects = lib.mkMerge (entityDeps ++ userDeps);
}
