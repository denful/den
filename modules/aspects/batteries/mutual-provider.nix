{ den, lib, ... }:
let
  description = ''
    Delivers what a user provides to its hosts (`provides.to-hosts`,
    `provides.<host>`) into each host's own configuration.

    Included in `den.schema.host.includes` by default. A host or fleet opts out
    with an exclude:

       den.schema.host.excludes = [ den.batteries.mutual-provider ];
  '';

  # A host-scope policy: it publishes the host's acceptance as context, which
  # the user scopes below it read. It does nothing in a user scope.
  accept =
    { host, ... }@ctx:
    lib.optional (!(ctx ? user) && host ? id_hash) (
      den.lib.policy.resolve { ${den.lib.acceptance.mutualProviderKey host} = true; }
    );
in
{
  # The battery is the policy itself: included by default on every host, it
  # adds no aspect node of its own.
  den.batteries.mutual-provider = {
    __isPolicy = true;
    name = "mutual-provider";
    inherit description;
    fn = accept;
    # Earlier configs called it with an argument (`den._.mutual-provider { }`).
    __functor = self: _: self;
  };

  den.schema.host.includes = [ den.batteries.mutual-provider ];
}
