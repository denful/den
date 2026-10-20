# nixosConfigurations per den.hosts.<sys>.<host>: host closure modules, then each user's (design-gen.md R4a).
denGen: {
  hosts =
    world: inputs:
    builtins.foldl' (a: b: a // b) { } (
      builtins.attrValues (
        builtins.mapAttrs (
          system: hs:
          builtins.mapAttrs (
            host: h:
            inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules =
                let
                  us = h.users;
                  r = denGen.route world.aspects (h // { inherit system; }) (builtins.attrNames us);
                  # shortcut: empty user classes falls back to schema default; no per-user override of schema.
                  hmClasses = u: if us.${u}.classes != [ ] then us.${u}.classes else world.schema.user.classes or [ ];
                in
                r.modules ++ r.hm inputs (builtins.filter (u: builtins.elem "homeManager" (hmClasses u)) (builtins.attrNames us));
            }
          ) hs
        ) world.hosts
      )
    );
}
