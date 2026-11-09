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

  # The lift is not an effect `admits` sees, so the battery reads the host's
  # admits itself (#694 §11a R7): denied, the host accepts nothing; under
  # `default = "deny"` it must be allowed, by the battery's record. The layers
  # are as for a delivery: the host's kind's schema, then its own aspect.
  gate =
    byDefault: host: publish:
    let
      kind = builtins.head (lib.splitString ":" host.id_hash);
      layers = [
        ((den.schema.${kind} or { }).admits or { })
        ((host.aspect or { }).admits or { })
      ];
      has = l: builtins.any (layer: builtins.elem den.batteries.user-aspects (layer.${l} or [ ])) layers;
      defaultDeny = builtins.any (layer: (layer.default or null) == "deny") layers;
    in
    if has "deny" then
      [ ]
    else if defaultDeny && !(has "allow") then
      throw (
        if byDefault then
          "den: ${host.name} receives users' content through the transition default (den.batteries.user-aspects) but admits.default = \"deny\"; add den.batteries.user-aspects to admits.allow, or set den.migrations.user-host-content.acknowledged = true"
        else
          "den: ${host.name} includes den.batteries.user-aspects but admits.default = \"deny\" and it is not in admits.allow; add it to admits.allow"
      )
    else
      publish;

  acceptFor = users: {
    __isPolicy = true;
    name = "user-aspects-accept(${argsName users})";
    fn =
      { host, ... }@ctx:
      lib.optionals (!(ctx ? user) && host ? id_hash) (
        gate false host [
          (den.lib.policy.resolve { ${acceptance.userAspectsKey host users} = { inherit users; }; })
        ]
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
      lib.optionals (!(ctx ? user) && !(ctx ? home) && host ? id_hash) (
        gate true host [ (den.lib.policy.resolve { ${acceptance.userAspectsDefaultKey host} = true; }) ]
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
