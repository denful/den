{ denTest, ... }:
{
  flake.tests.os-class = {

    test-forwards-to-nixos-and-darwin = denTest (
      {
        den,
        lib,
        igloo,
        apple,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.aarch64-darwin.apple.users.tux = { };

        # user contributes to both NixOS and MacOS
        den.aspects.tux = {
          os.networking.hostName = "from-os-class";
        };

        expr = {
          nixos = igloo.networking.hostName;
          macos = apple.networking.hostName;
        };
        expected = {
          nixos = "from-os-class";
          macos = "from-os-class";
        };
      }
    );

    test-os-class-from-parametric-include = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          includes = [
            (
              { host, ... }:
              lib.optionalAttrs (host.class == "nixos") {
                os.networking.hostName = "from-parametric";
              }
            )
          ];
        };

        expr = igloo.networking.hostName;
        expected = "from-parametric";
      }
    );
  };
}
