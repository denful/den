{ lib, ... }:
let
  description = ''
    Sets the system hostname as defined in `den.hosts.<name>.hostName`:

    Works on NixOS/Darwin/WSL.

    ## Usage

       den.defaults.includes = [ den.batteries.hostname ];
  '';

  setHostname =
    { host, ... }:
    {
      name = "hostname/os";
    }
    # A synthetic host identity (a `user@host` home with no declared host) has
    # no OS class to set a hostname on; gate to real, class-bearing hosts.
    // lib.optionalAttrs (host ? class) {
      ${host.class}.networking.hostName = host.hostName;
    };
in
{
  den.batteries.hostname = {
    name = "hostname";
    inherit description;
    includes = [ setHostname ];
  };
}
