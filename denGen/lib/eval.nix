# evalDen: Gen-side eval of the captured `den` leaf modules -> world (design-gen.md §3 steps 2-4). No routing yet (R2+).
denGen: {
  evalDen =
    denModules:
    let
      inner = denGen.genLib.evalModules {
        modules = [
          denGen.view.module
          denGen.batteries.module
          { _module.args.den = world; }
        ] ++ denModules;
      };
      cfg = inner.config;
      aspects = denGen.view.mkAspects cfg;
      hostNames = builtins.concatMap builtins.attrNames (builtins.attrValues cfg.hosts);
      world = {
        inherit aspects;
        inherit (cfg) hosts;
        batteries.primary-user = aspects.primary-user;
        batteries.define-user = aspects.define-user;
        batteries.hostname = aspects.hostname;
        lib.nh.denPackages = denGen.nh hostNames;
        lib.closure = denGen.closure aspects;
        # host entity by name (system = its attr-path key)
        host = name: builtins.head (builtins.concatLists (builtins.attrValues (builtins.mapAttrs (system: hs: if hs ? ${name} then [ (hs.${name} // { inherit system; }) ] else [ ]) cfg.hosts)));
        lib.userModules = h: u: (denGen.route aspects (world.host h) [ ]).userModules u;
      };
    in
    world;
}
