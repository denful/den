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
              modules = (denGen.route world.aspects host (builtins.attrNames (h.users or { }))).modules;
            }
          ) hs
        ) world.hosts
      )
    );
}
