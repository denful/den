# templates/ci/modules/internal-api/path-set-by-scope.nix
{ denTest, ... }:
{
  flake.tests.path-set-by-scope = {
    test-bucket-by-scope = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx;
        hostRoot = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
        run = fxLib.pipeline.fxFullResolve {
          class = "nixos";
          ctx = fxLib.aspect.ctxFromHandlers (hostRoot.__scopeHandlers or { });
          self = den.lib.aspects.normalizeRoot hostRoot;
        };
        psbs = (run.state.pathSetByScope or (_: { })) null;
        tuxScopes = builtins.filter (s: builtins.match ".*user=tux.*" s != null) (builtins.attrNames psbs);
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.aspect1.homeManager.programs.atuin.enable = true;
        den.aspects.igloo.provides.tux.includes = [ den.aspects.aspect1 ];

        expr = tuxScopes != [ ] && builtins.any (s: (psbs.${s} or { }) ? "aspect1") tuxScopes;
        expected = true;
      }
    );

    test-resolveWithPaths-shape = denTest (
      { den, ... }:
      let
        hostRoot = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
        r = den.lib.aspects.resolveWithPaths "nixos" hostRoot;
        plain = den.lib.aspects.resolve "nixos" hostRoot;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        expr = {
          hasImports = r ? imports;
          hasPaths = r ? pathSetByScope;
          plainCleanlyImportsOnly = builtins.attrNames plain == [ "imports" ];
        };
        expected = {
          hasImports = true;
          hasPaths = true;
          plainCleanlyImportsOnly = true;
        };
      }
    );

    test-mkProjectedHasAspect = denTest (
      { den, ... }:
      let
        mk = den.lib.aspects.mkProjectedHasAspect;
        h = mk {
          pathSetByScope = {
            "id:abc" = {
              "foo" = true;
            };
          };
          key = "id:abc";
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.nixos = { };
        den.aspects.bar.nixos = { };
        expr = {
          hasFoo = h den.aspects.foo;
          hasBar = h den.aspects.bar;
          any = h.forAnyClass den.aspects.foo;
        };
        expected = {
          hasFoo = true;
          hasBar = false;
          any = true;
        };
      }
    );

    test-entity-exposes-psbs = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.aspect1.homeManager.programs.atuin.enable = true;
        den.aspects.igloo.provides.tux.includes = [ den.aspects.aspect1 ];

        expr =
          let
            psbs = den.hosts.x86_64-linux.igloo.__pathSetByScope;
          in
          builtins.isAttrs psbs && builtins.any (s: (psbs.${s} or { }) ? "aspect1") (builtins.attrNames psbs);
        expected = true;
      }
    );
  };
}
