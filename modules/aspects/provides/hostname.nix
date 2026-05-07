{ ... }:
let
  description = ''
    Sets the system hostname as defined in `den.hosts.<name>.hostName`:

    Works on NixOS/Darwin/WSL.

    ## Usage

       den.defaults.includes = [ den.provides.hostname ];
  '';

  setHostname =
    { host, ... }:
    {
      name = "hostname/os";
      ${host.class}.networking.hostName = host.hostName;
    };
in
{
  den.provides.hostname = {
    name = "hostname";
    inherit description;
    includes = [ setHostname ];
  };
}
