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
  # `all` for the bare battery; a list renders as JSON, so it never reads
  # `all` and no separator can join two lists into one name.
  argsName = users: if users == null then "all" else den.lib.argsName.setOf users;

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
    # Keyed by den's path wherever it is included, so equal arguments
    # included twice at a scope are one battery (gate dedup), as unfree is.
    meta.aspect-chain = [
      "den"
      "batteries"
    ];
    inherit description;
    includes = [ (acceptFor users) ];
  };

  # The transition default, on every host until den.lib.migrations
  # removalDate: its own policy and key, so an explicit include is told apart
  # from it. Named below the battery's path, so excluding the battery
  # excludes it by origin.
  transitionDefault = {
    __isPolicy = true;
    name = "${(battery null).name}/transition-default";
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
    __transitionDefaultPolicy = transitionDefault;
  };

  # On every entity kind, so a nested kind with its own class (a guest that is
  # its own host) gets it too; it acts only where `host` is bound and `user`
  # is not.
  den.default.includes = lib.optional den.lib.migrations.transitionActive transitionDefault;
}
