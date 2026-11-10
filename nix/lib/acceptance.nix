# Context keys a host publishes (as enrichment) to accept its users' host-class
# output. Keyed by the host's id_hash: enrichment persists into child scopes, so
# a guest nested under an accepting host must not inherit the acceptance.
{ lib, den-lib, ... }:
let
  mutualProviderRoot = "den-mutual-provider/";
  userAspectsRoot = "den-user-aspects/";
  userAspectsPrefix = host: "${userAspectsRoot}${host.id_hash}/";
  # Published by user-aspects' transition default only: outside the explicit
  # prefix, so it never reads as an explicit acceptance.
  userAspectsDefaultKey = host: "${userAspectsRoot}default/${host.id_hash}";

  # The users a host accepts, from every user-aspects key it published; null
  # means all of them.
  acceptedUsers =
    ctx: host:
    let
      lists = map (k: ctx.${k}.users) (
        builtins.filter (lib.hasPrefix (userAspectsPrefix host)) (builtins.attrNames ctx)
      );
    in
    if lists == [ ] then
      [ ]
    else if builtins.any (l: l == null) lists then
      null
    else
      lib.unique (builtins.concatLists lists);
  acceptsExplicitly =
    ctx: host: user:
    let
      accepted = acceptedUsers ctx host;
    in
    host ? id_hash && (accepted == null || builtins.elem (user.name or null) accepted);
in
{
  # An aspect resolved at a scope's full context (as the scope itself resolves
  # it), for a delivery that carries the aspect's host-class output.
  atCtx =
    ctx: aspect:
    aspect
    // {
      __scopeHandlers = den-lib.aspects.fx.handlers.constantHandler (
        builtins.removeAttrs ctx [ "__entityKind" ]
      );
    };

  # Acceptance keys are den-internal context: they must not count as context
  # an exact-match function sees.
  isAcceptanceKey = k: lib.hasPrefix mutualProviderRoot k || lib.hasPrefix userAspectsRoot k;

  mutualProviderKey = host: "${mutualProviderRoot}${host.id_hash}";
  # Published by mutual-provider's transition default only (until
  # den.lib.migrations.removalDate).
  mutualProviderDefaultKey = host: "${mutualProviderRoot}default/${host.id_hash}";

  # One key per distinct argument set, so two identical includes write the same
  # key (enrichment is merged shallowly, last write wins).
  userAspectsKey =
    host: users: "${userAspectsPrefix host}${builtins.hashString "sha256" (builtins.toJSON users)}";

  inherit acceptedUsers;

  # Whether the host accepts this user through user-aspects. A user scope's
  # stored context carries its host's keys, so `ctx` may be either.
  # Through user-aspects, explicitly or through its transition default (until
  # den.lib.migrations.removalDate).
  accepts =
    ctx: host: user:
    host ? id_hash && (ctx ? ${userAspectsDefaultKey host} || acceptsExplicitly ctx host user);

  inherit userAspectsDefaultKey acceptsExplicitly;
}
