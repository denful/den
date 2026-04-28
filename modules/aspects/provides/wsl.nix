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

  fwd =
    { host, aspect-chain, ... }:
    den.provides.forward {
      each = lib.singleton true;
      fromClass = _: "wsl";
      intoClass = _: host.class;
      intoPath = _: [ "wsl" ];
      fromAspect = _: lib.head aspect-chain;
      guard = { options, ... }: options ? wsl;
    };

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
      inherit description;
      ${host.class} = {
        imports = [ host.wsl.module ];
        wsl.enable = true;
      };
      includes = [ fwd ];
    };

in
{
  den.classes.wsl.description = "WSL support class forwarding to host OS";

  den.aspects.wsl-host-aspect = wsl-host-aspect;

  den.schema.host.imports = [ hostConf ];

  den.policies.host-to-wsl-host =
    {
      __entityKind ? null,
      host,
      ...
    }:
    if __entityKind != "host" then
      [ ]
    else if host.class == "nixos" && (host.wsl or { }).enable or false then
      [
        (den.lib.policy.resolve.to "wsl-host" { inherit host; })
        (den.lib.policy.include wsl-host-aspect)
      ]
    else
      [ ];
}
