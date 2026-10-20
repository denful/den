# nixosConfigurations per den.hosts.<sys>.<host>: host closure modules, then each user's (design-gen.md R4a).
denGen: {
  hosts =
    world: inputs:
    let
      flat = builtins.foldl' (a: b: a // b) { } (
        builtins.attrValues (builtins.mapAttrs (system: builtins.mapAttrs (_: h: h // { inherit system; })) world.hosts)
      );
      pol = denGen.policy world;
      # system-to-os-outputs excluded (fleet): only `instantiate` effects build hosts
      built = if pol.osOutputs then flat else inputs.nixpkgs.lib.filterAttrs (n: _: builtins.elem n pol.instantiated) flat;
      # lazy fixpoint: channel emissions read other hosts' final configs
      systems = builtins.mapAttrs (
        _: h0:
        inputs.nixpkgs.lib.nixosSystem {
          inherit (h0) system;
          modules =
            let
              us = pol.usersOf h0;
              h = h0 // { users = us; };
              r = denGen.route world.schema world.aspects h (builtins.attrNames us);
              # policy-resolved users carry the registry's default classes ["user"], not an explicit choice; only declared host.users override schema.
              # shortcut: empty user classes falls back to schema default.
              hmClasses = u: if h0.users ? ${u} && us.${u}.classes != [ ] then us.${u}.classes else world.schema.user.classes or [ ];
              allHosts = builtins.mapAttrs (n: e: { host = e; config = systems.${n}.config; }) flat;
            in
            r.modules
            ++ r.hm inputs (builtins.filter (u: builtins.elem "homeManager" (hmClasses u)) (builtins.attrNames us))
            ++ denGen.channels.modules world allHosts h (pol.siblingsOf h (builtins.attrNames flat));
        }
      ) built;
    in
    systems;
}
