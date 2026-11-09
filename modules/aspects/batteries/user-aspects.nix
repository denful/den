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

in
{
  den.batteries.user-aspects = battery null // {
    __functor = _: { users }: battery users;
  };
}
