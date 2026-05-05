{ den, lib, ... }:
let
  description = ''
    The `os` class is a convenience for settings that should be forwarded
    into both `nixos` and `darwin` classes.

    This class is enabled by default.

    # Usage

      den.aspects.my-host = {
        os.networking.hostName = "foo";
      };

  '';
in
{
  den.classes.os.description = "Convenience class forwarding to both nixos and darwin";

  # Built-in policy: route os class content to the host's class.
  # Replaces os-host-fwd and os-user-fwd forward aspects.
  # Fires in every scope where host is bound (including user scopes),
  # routing per-scope os content to the host's target class.
  den.default.includes = [ den.policies.os-to-host ];

  den.policies.os-to-host =
    { host, ... }:
    lib.optional
      (builtins.elem host.class [
        "nixos"
        "darwin"
      ])
      (
        den.lib.policy.route {
          fromClass = "os";
          intoClass = host.class;
          path = [ ];
        }
      );
}
