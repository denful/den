# Test os-class forwarding from host aspects (not user aspects).
{ denTest, lib, ... }:
{
  flake.tests.os-class-host = {

    # Host aspect sets os.networking.hostName — should forward to nixos.
    test-host-os-forwards-to-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          os.networking.hostName = "from-os-class";
        };

        expr = igloo.networking.hostName;
        expected = "from-os-class";
      }
    );

    # os forwards to BOTH nixos and darwin simultaneously.
    test-host-os-forwards-to-both = denTest (
      {
        den,
        igloo,
        apple,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.aarch64-darwin.apple.users.tux = { };

        den.aspects.shared-base = {
          os.networking.hostName = "shared";
        };

        den.aspects.igloo.includes = [ den.aspects.shared-base ];
        den.aspects.apple.includes = [ den.aspects.shared-base ];

        expr = {
          nixos = igloo.networking.hostName;
          darwin = apple.networking.hostName;
        };
        expected = {
          nixos = "shared";
          darwin = "shared";
        };
      }
    );

    # os from parametric include on host aspect.
    test-host-os-from-parametric = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          includes = [
            (
              { host, ... }:
              {
                os.networking.hostName = host.name;
              }
            )
          ];
        };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # os with module-system function (Tier 3 style).
    test-host-os-module-function = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          os =
            { lib, ... }:
            {
              environment.variables.OS_CLASS = "works";
            };
        };

        expr = igloo.environment.variables.OS_CLASS;
        expected = "works";
      }
    );

  };
}
