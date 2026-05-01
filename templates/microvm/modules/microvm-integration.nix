{
  den,
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (den.lib.policy) resolve include;

  # extends den.schema.host with MicroVM specific options
  extendHostSchema =
    { host, ... }:
    {
      options.microvm.module = lib.mkOption {
        description = "MicroVM microvm.nix module";
        type = lib.types.deferredModule;
        default = inputs.microvm."${host.class}Modules".microvm;
      };

      options.microvm.hostModule = lib.mkOption {
        description = "MicroVM host.nix module";
        type = lib.types.deferredModule;
        default = inputs.microvm."${host.class}Modules".host;
      };

      # Declarative Guest VMs built with Host.
      options.microvm.guests = lib.mkOption {
        type = lib.types.listOf lib.types.raw;
        default = [ ];
        defaultText = lib.literalExpression "[ ]";
        description = ''
          Guest MicroVMs.
          Value is a list of Den hosts: [ den.hosts.x86_64-linux.foo-microvm ]

          When non empty, Host imports <microvm>/host.nix module
          and starts our Den microvm-host context pipeline.

          See: https://microvm-nix.github.io/microvm.nix/host.html
               https://microvm-nix.github.io/microvm.nix/declarative.html
        '';
      };

      options.microvm.sharedNixStore = lib.mkEnableOption "Auto share nix store from host";
      config.microvm.sharedNixStore = lib.mkDefault true;
    };

  # aspect configuring a guest vm at the host level (Declarative in MicroVM parlance)
  # See: https://microvm-nix.github.io/microvm.nix/declarative.html
  microvmGuestProvide =
    { host }:
    { host, vm }:
    {
      includes =
        let
          sharedNixStore = lib.optionalAttrs host.microvm.sharedNixStore {
            ${host.class}.microvm.vms.${vm.name}.config.microvm.shares = [
              {
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                tag = "ro-store";
                proto = "virtiofs";
              }
            ];
          };

          # forwards guest nixos configuration into host: microvm.vms.<vm-name>.config
          osFwd = den.provides.forward {
            each = lib.singleton true;
            fromClass = _: vm.class;
            intoClass = _: host.class;
            intoPath = _: [
              "microvm"
              "vms"
              vm.name
              "config"
            ];
            # calling host-pipeline ensure all Den features supported on guest
            fromAspect = _: den.lib.resolveEntity "host" { host = vm; };
          };

          # forwards guest microvm class into host: microvm.vms.<vm-name>
          microvmClass = den.provides.forward {
            each = lib.singleton true;
            fromClass = _: "microvm";
            intoClass = _: host.class;
            intoPath = _: [
              "microvm"
              "vms"
              vm.name
            ];
            fromAspect = _: vm.aspect;
          };

        in
        [
          sharedNixStore
          osFwd
          microvmClass
        ];
    };

in
{
  den.schema.host.policies.host-to-microvm-host =
    {
      host,
      ...
    }:
    lib.optionals (host.microvm.guests != [ ]) [
      (resolve.to "microvm-host" { inherit host; })
      (include (
        { host }:
        {
          ${host.class}.imports = [ host.microvm.hostModule ];
        }
      ))
    ];

  den.schema.microvm-host.policies.microvm-host-to-microvm-guest =
    {
      host,
      ...
    }:
    lib.concatMap (vm: [
      (resolve.to "microvm-guest" {
        inherit host vm;
      })
      (include microvmGuestProvide)
    ]) host.microvm.guests;
  den.schema.microvm-host.includes = [ ];
  den.schema.microvm-guest.includes = [ ];
  den.schema.host.imports = [ extendHostSchema ];
}
