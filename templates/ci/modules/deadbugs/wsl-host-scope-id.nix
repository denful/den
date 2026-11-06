# Regression: the wsl battery resolved its `wsl-host` scope with only `host`
# bound, so mkScopeId gave it the host's own scope id. Other hosts'
# pipe.collectAll then missed the WSL host, and the WSL host saw its own pool
# twice.
{ denTest, ... }:
{
  flake.tests.deadbugs.wsl-host-scope-id = {

    test-collectAll-reaches-wsl-host = denTest (
      {
        den,
        lib,
        igloo,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg = {
          users.tux = { };
          wsl.enable = true;
          # Stub instead of NixOS-WSL: the bug is in Den's scoping, not in WSL
          wsl.module = {
            options.wsl = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
          };
        };

        den.quirks.tag.description = "one tag per host";
        den.aspects.igloo.tag = "igloo";
        den.aspects.iceberg.tag = "iceberg";

        den.policies.roster =
          { host, ... }:
          [
            (den.lib.policy.pipe.from "tag" [ (den.lib.policy.pipe.collectAll ({ host, ... }: true)) ])
          ];
        den.aspects.show.nixos =
          { tag, ... }:
          {
            environment.etc.tags.text = builtins.toJSON (builtins.sort builtins.lessThan tag);
          };
        den.schema.host.includes = [
          den.policies.roster
          den.aspects.show
        ];

        expr = {
          igloo = igloo.environment.etc.tags.text;
          iceberg = iceberg.environment.etc.tags.text;
        };
        expected = {
          igloo = ''["iceberg","igloo"]'';
          iceberg = ''["iceberg","igloo"]'';
        };
      }
    );

  };
}
