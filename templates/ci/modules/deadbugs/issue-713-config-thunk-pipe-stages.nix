# A config-dependent quirk value (`{ config, ... }: …`) emitted on the
# consuming host itself is deferred to the host's evalModules fixpoint. The
# pipe's filter/transform stages must still apply to it once resolved; before
# the fix they were skipped for the local value only, while collected peer
# values went through them.
{ denTest, lib, ... }:
let
  setup =
    { den, stages }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.x86_64-linux.iceberg.users.alice = { };
      den.quirks.http-backends.description = "HTTP backends";
      den.policies.backends =
        { host, ... }:
        [
          (den.lib.policy.pipe.from "http-backends" (
            [ (den.lib.policy.pipe.collectAll ({ host, ... }: true)) ] ++ stages den.lib.policy.pipe
          ))
        ];
      den.schema.host.includes = [ den.policies.backends ];
      den.aspects.iceberg.http-backends =
        { config, ... }:
        {
          addr = "10.0.0.2";
          port = 80;
        };
      den.aspects.igloo = {
        includes = [ den.aspects.haproxy ];
        http-backends =
          { config, ... }:
          {
            addr = "10.0.0.1";
            port = 8080;
          };
      };
      den.aspects.haproxy.nixos =
        { http-backends, ... }:
        {
          environment.etc.backends.text = builtins.toJSON (
            lib.sort lib.lessThan (map (b: b.url or "untransformed:${b.addr}") http-backends)
          );
        };
    };
in
{
  flake.tests.issue-713-config-thunk-pipe-stages = {

    test-transform-applies-to-local-config-thunk = denTest (
      { den, igloo, ... }:
      setup {
        inherit den;
        stages = pipe: [ (pipe.transform (b: b // { url = "http://${b.addr}:${toString b.port}"; })) ];
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = builtins.toJSON [
          "http://10.0.0.1:8080"
          "http://10.0.0.2:80"
        ];
      }
    );

    test-filter-applies-to-local-config-thunk = denTest (
      { den, igloo, ... }:
      setup {
        inherit den;
        stages = pipe: [
          (pipe.filter (b: b.port == 80))
          (pipe.transform (b: b // { url = "http://${b.addr}"; }))
        ];
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = builtins.toJSON [ "http://10.0.0.2" ];
      }
    );

  };
}
