# nixosConfigurations per den.hosts.<sys>.<host>: host closure modules, then each user's (design-gen.md R4a).
denGen: {
  hosts =
    world: inputs:
    let
      flat = builtins.foldl' (a: b: a // b) { } (
        builtins.attrValues (builtins.mapAttrs (system: builtins.mapAttrs (_: h: h // { inherit system; })) world.hosts)
      );
      # lazy fixpoint: channel emissions read other hosts' final configs
      systems = builtins.mapAttrs (
        _: h:
        inputs.nixpkgs.lib.nixosSystem {
          inherit (h) system;
          modules =
            let
              us = h.users;
              r = denGen.route world.aspects h (builtins.attrNames us);
              # shortcut: empty user classes falls back to schema default; no per-user override of schema.
              hmClasses = u: if us.${u}.classes != [ ] then us.${u}.classes else world.schema.user.classes or [ ];
              allHosts = builtins.mapAttrs (n: e: { host = e; config = systems.${n}.config; }) flat;
            in
            r.modules
            ++ r.hm inputs (builtins.filter (u: builtins.elem "homeManager" (hmClasses u)) (builtins.attrNames us))
            ++ denGen.channels.modules world allHosts h;
        }
      ) flat;
    in
    systems;
}
