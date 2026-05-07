{
  den,
  lib,
  inputs,
  ...
}:
let
  description = ''
    Enables WSL support on NixOS. Using NixOS-WSL project.

    # Requirements

    - have an inputs.nixos-wsl input or specify host.wsl.module.
    - host.class is "nixos"

    # Usage

    On a single host:

       den.hosts.x86_64-linux.igloo.wsl.enable = true;

    On ALL hosts (works only on nixos class hosts):

       den.schema.host.wsl.enable = true;
  '';

  hostConf.options.wsl = {
    enable = lib.mkEnableOption "Enable WSL on this host";
    module = lib.mkOption {
      description = "The NixOS-WSL module";
      type = lib.types.deferredModule;
      defaultText = lib.literalExpression "inputs.nixos-wsl.nixosModules.default";
      default = inputs.nixos-wsl.nixosModules.default;
    };
  };

  wsl-host-aspect =
    { host }:
    {
      name = "wsl/${host.name}";
      inherit description;
      ${host.class} = {
        imports = [ host.wsl.module ];
        wsl.enable = true;
      };
    };

in
{
  den.classes.wsl.description = "WSL support class forwarding to host OS";

  den.aspects.wsl-host-aspect = wsl-host-aspect;

  den.schema.host.imports = [ hostConf ];

  den.policies.host-to-wsl-host =
    {
      host,
      ...
    }:
    if host.class == "nixos" && (host.wsl or { }).enable or false then
      [
        (den.lib.policy.resolve.to "wsl-host" { inherit host; })
        (den.lib.policy.include wsl-host-aspect)
      ]
    else
      [ ];

  den.schema.host.includes = [ den.policies.host-to-wsl-host ];

  den.default.includes = [ den.policies.wsl-to-host ];

  # Route wsl class content to host class at ["wsl"]. Fires in ALL scopes
  # (host + user) so user-scope wsl content (e.g., from primary-user) is
  # captured. Guard ensures injection only when wsl module is loaded.
  den.policies.wsl-to-host =
    { host, ... }:
    lib.optional ((host.wsl or { }).enable or false) (
      den.lib.policy.route {
        fromClass = "wsl";
        intoClass = host.class;
        path = [ "wsl" ];
        guard = { options, ... }: options ? wsl;
      }
    );
}
