# Context keys a host publishes (as enrichment) to accept its users' host-class
# output. Keyed by the host's id_hash: enrichment persists into child scopes, so
# a guest nested under an accepting host must not inherit the acceptance.
{ lib, den-lib, ... }:
let
  mutualProviderRoot = "den-mutual-provider/";
  userAspectsRoot = "den-user-aspects/";
  userAspectsPrefix = host: "${userAspectsRoot}${host.id_hash}/";
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

  # One key per distinct argument set, so two identical includes write the same
  # key (enrichment is merged shallowly, last write wins).
  userAspectsKey =
    host: users: "${userAspectsPrefix host}${builtins.hashString "sha256" (builtins.toJSON users)}";
}
