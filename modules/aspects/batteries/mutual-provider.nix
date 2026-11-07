{ den, lib, ... }:
let
  description = ''
    Delivers what a user provides to its hosts (`provides.to-hosts`,
    `provides.<host>`) into each host's own configuration. Include it on the
    hosts that should receive it:

       den.schema.host.includes = [ den.batteries.mutual-provider ];

    Until ${den.lib.migrations.removalDate} it is also on by default, as a
    transition default (see `den.migrations.user-host-content`). A host or
    fleet opts out with an exclude, which covers the default too:

       den.schema.host.excludes = [ den.batteries.mutual-provider ];
  '';

  # A host-scope policy: it publishes the host's acceptance as context, which
  # the user scopes below it read. It does nothing in a user scope.
  acceptWith =
    keyOf:
    { host, ... }@ctx:
    lib.optional (!(ctx ? user) && host ? id_hash) (den.lib.policy.resolve { ${keyOf host} = true; });

  # The transition default, on every host until the removal date: its own
  # policy, so an explicit include is told apart from it.
  defaultForm = {
    __isPolicy = true;
    name = "mutual-provider-default";
    fn = acceptWith den.lib.acceptance.mutualProviderDefaultKey;
  };
in
{
  # The battery is the policy itself: it adds no aspect node of its own.
  den.batteries.mutual-provider = {
    __isPolicy = true;
    name = "mutual-provider";
    inherit description;
    fn = acceptWith den.lib.acceptance.mutualProviderKey;
    # Excluding the battery excludes its default form too. Temporary: PR 4's
    # origin-matched excludes cover this generally, and the default goes on
    # the removal date.
    __defaultForm = defaultForm;
    # Earlier configs called it with an argument (`den._.mutual-provider { }`).
    __functor = self: _: self;
  };

  # On every entity kind, so a nested kind with its own class (a guest that is
  # its own host) gets it too; it acts only where `host` is bound and `user`
  # is not.
  den.default.includes = lib.optional den.lib.migrations.transitionActive defaultForm;
}
