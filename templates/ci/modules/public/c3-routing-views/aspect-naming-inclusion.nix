# Aspects nest at any depth without `provides`, reach a host by any of the
# four inclusion routes, and `<aspect>._` includes only depth-1 children.
{ denTest, lib, ... }:
{
  flake.tests.c3.aspect-naming-inclusion = {

    test-route-host-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.bar.baz.nixos.networking.hostName = "deep";
        den.aspects.igloo.includes = [ den.aspects.foo.bar.baz ];
        expr = igloo.networking.hostName;
        expected = "deep";
      }
    );

    test-route-policy = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.bar.baz.nixos.networking.hostName = "via-policy";
        den.policies.add-baz = { host, ... }: [ (den.lib.policy.include den.aspects.foo.bar.baz) ];
        den.schema.host.includes = [ den.policies.add-baz ];
        expr = igloo.networking.hostName;
        expected = "via-policy";
      }
    );

    test-route-schema = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.bar.baz.nixos.networking.hostName = "via-schema";
        den.schema.host.includes = [ den.aspects.foo.bar.baz ];
        expr = igloo.networking.hostName;
        expected = "via-schema";
      }
    );

    test-route-default = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.bar.baz.nixos.networking.hostName = "via-default";
        den.default.includes = [ den.aspects.foo.bar.baz ];
        expr = igloo.networking.hostName;
        expected = "via-default";
      }
    );

    test-nested-not-included-by-itself = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.bar.baz.nixos.networking.hostName = "never";
        den.aspects.igloo.includes = [ den.aspects.foo ];
        expr = igloo.networking.hostName;
        expected = "nixos";
      }
    );

    test-underscore-glob-direct-and-provides = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo = {
          nixos.networking.hostName = "foo-own";
          direct.nixos.services.openssh.enable = true;
          provides.legacy.nixos.services.timesyncd.enable = true;
          direct.deeper.nixos.services.prometheus.enable = true;
        };
        den.aspects.igloo.includes = [ den.aspects.foo._ ];
        expr = {
          inherit (igloo.networking) hostName;
          direct = igloo.services.openssh.enable;
          legacy = igloo.services.timesyncd.enable;
          grandchild = igloo.services.prometheus.enable;
        };
        expected = {
          hostName = "nixos";
          direct = true;
          legacy = true;
          grandchild = false;
        };
      }
    );

    test-provides-alias-same-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.foo.provides.bar.nixos.networking.hostName = "legacy";
        den.aspects.igloo.includes = [ den.aspects.foo.bar ];
        expr = [
          igloo.networking.hostName
          (den.aspects.foo._ ? bar)
        ];
        expected = [
          "legacy"
          true
        ];
      }
    );

    test-freeform-host-attr = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          gpu = "nvidia";
        };
        den.aspects.igloo.gpu =
          { host, ... }: lib.optionalAttrs (host ? gpu) { nixos.networking.hostName = "gpu-${host.gpu}"; };
        den.aspects.igloo.includes = [ den.aspects.igloo.gpu ];
        expr = igloo.networking.hostName;
        expected = "gpu-nvidia";
      }
    );

    test-schema-host-attr = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host =
          { lib, ... }:
          {
            options.gpu = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
          };
        den.aspects.igloo.gpu =
          { host, ... }: lib.optionalAttrs (host.gpu != null) { nixos.networking.hostName = "gpu"; };
        den.aspects.igloo.includes = [ den.aspects.igloo.gpu ];
        expr = igloo.networking.hostName;
        expected = "nixos";
      }
    );
  };
}
