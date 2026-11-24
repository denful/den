# nix/lib/types.nix — re-export shim for backwards compatibility
#
# Entity types have been split into per-entity files under nix/lib/entities/.
# This shim re-exports for any external consumers.
args:
let
  host = import ./entities/host.nix args;
  home = import ./entities/home.nix args;
  user = import ./entities/user.nix args;
in
{
  inherit (user) usersOption;
  inherit (host) hostsOption;
  inherit (home) homesOption;
}
