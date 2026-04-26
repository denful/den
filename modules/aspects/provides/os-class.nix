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
  den.stages.host.includes = [ host-os-fwd ];
  den.stages.user.includes = [ user-os-fwd ];

  den.schema.classes.os.description = "Convenience class forwarding to both nixos and darwin";
  den._classNames.os = true;
}
