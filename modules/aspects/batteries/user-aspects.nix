{ den, lib, ... }:
let
  inherit (den.lib) acceptance;

  description = ''
    A host accepts its users' whole host-class output, their own `nixos` /
    `darwin` / `os` included. Declared on the host side only.

       den.aspects.igloo.includes = [ den.batteries.user-aspects ];
       den.aspects.igloo.includes = [ (den.batteries.user-aspects { users = [ "tux" ]; }) ];
       den.schema.host.includes = [ den.batteries.user-aspects ];
  '';

  # A host-scope policy: it publishes the host's acceptance as context. The
  # delivery that reads it lands with the bounded merge (#694). Inert in a user
  # scope, so including it on a user accepts nothing.
  # Named per argument set: identical includes deduplicate, different ones
  # each publish.
  argsName = users: if users == null then "all" else builtins.concatStringsSep "," users;

  acceptFor = users: {
    __isPolicy = true;
    name = "user-aspects-accept(${argsName users})";
    fn =
      { host, ... }@ctx:
      lib.optional (!(ctx ? user) && host ? id_hash) (
        den.lib.policy.resolve { ${acceptance.userAspectsKey host users} = { inherit users; }; }
      );
  };

  battery = users: {
    name = "user-aspects(${argsName users})";
    inherit description;
    includes = [ (acceptFor users) ];
  };

  # The transition default, on every host until den.lib.migrations
  # removalDate: its own policy and key, so an explicit include is told apart
  # from it.
  defaultForm = {
    __isPolicy = true;
    name = "user-aspects-default";
    fn =
      { host, ... }@ctx:
      # Not at a standalone home, which binds a host it doesn't belong to.
      lib.optional (!(ctx ? user) && !(ctx ? home) && host ? id_hash) (
        den.lib.policy.resolve { ${acceptance.userAspectsDefaultKey host} = true; }
      );
  };
in
{
  den.batteries.user-aspects = battery null // {
    __functor = _: { users }: battery users;
    # Excluding the battery excludes its transition default too. Temporary:
    # PR 4's origin-matched excludes cover this generally.
    __defaultForm = defaultForm;
  };

  # On every entity kind, so a nested kind with its own class (a guest that is
  # its own host) gets it too; it acts only where `host` is bound and `user`
  # is not.
  den.default.includes = lib.optional den.lib.migrations.transitionActive defaultForm;
}
