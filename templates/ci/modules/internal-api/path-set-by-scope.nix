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
  };
}
