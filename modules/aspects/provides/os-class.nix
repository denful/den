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

  mkOsFwd =
    ctx: aspect:
    den.provides.forward {
      each = [
        "nixos"
        "darwin"
      ];
      fromClass = _: "os";
      intoClass = lib.id;
      intoPath = _: [ ];
      fromAspect = _: aspect;
      fromCtx = _: ctx;
    };

  # Host-level os-class: forwards os content from the host's aspect.
  host-os-fwd = { host, ... }: mkOsFwd { inherit host; } host.aspect;

  # User-level os-class: forwards os content from each user's aspect.
  user-os-fwd = { user, host, ... }: mkOsFwd { inherit host user; } user.aspect;

in
{
  den.aspects.os-host-fwd = host-os-fwd;
  den.aspects.os-user-fwd = user-os-fwd;

  # Empty entityIncludes kept for schema gating (options.nix uses these
  # keys to decide which entity kinds get `resolved` / pipeline wiring).
  # Removed in Task 4 when the gating mechanism itself is replaced.
  den.entityIncludes.host = [ ];
  den.entityIncludes.user = [ ];

  den.classes.os.description = "Convenience class forwarding to both nixos and darwin";
}
