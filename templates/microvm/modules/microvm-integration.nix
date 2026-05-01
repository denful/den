{
  den,
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (den.lib.policy) resolve include route;

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

in
{
  # Register the microvm class so the pipeline recognizes microvm keys
  # in guest aspects and collects them in scopedClassImports.
  den.classes.microvm.description = "MicroVM guest configuration (microvm.nix options)";

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
    ]) host.microvm.guests;

  # Guest VM policy: resolve VM as a host entity within the pipeline's scope
  # tree, then route its class modules into the actual host's configuration.
  den.schema.microvm-guest.policies.microvm-guest-resolve-vm =
    {
      host,
      vm,
      ...
    }:
    let
      sharedNixStoreModule = lib.optionalAttrs host.microvm.sharedNixStore {
        ${host.class}.microvm.vms.${vm.name}.config.microvm.shares = [
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
        ];
      };
    in
    [
      # Resolve VM as a host entity — its class modules land in a child scope.
      # Pass __microvmHost so the child host policy can route modules back.
      (resolve.to "host" {
        host = vm;
        __microvmHost = host;
      })
      # Inject shared nix store config into actual host
      (include sharedNixStoreModule)
    ];

  # When a host is resolved within a microvm-guest context (__microvmHost present),
  # route the VM's class modules and microvm class modules back to the actual host.
  den.schema.host.policies.microvm-vm-route-back =
    {
      host,
      __microvmHost ? null,
      ...
    }:
    lib.optionals (__microvmHost != null) [
      # Route VM's OS class modules (e.g., nixos) into actual host at
      # microvm.vms.<vm-name>.config
      (route {
        fromClass = host.class;
        intoClass = __microvmHost.class;
        path = [
          "microvm"
          "vms"
          host.name
          "config"
        ];
      })
      # Route VM's microvm class modules into actual host at
      # microvm.vms.<vm-name>
      (route {
        fromClass = "microvm";
        intoClass = __microvmHost.class;
        path = [
          "microvm"
          "vms"
          host.name
        ];
      })
    ];

  den.schema.microvm-host.includes = [ ];
  den.schema.microvm-guest.includes = [ ];
  den.schema.host.imports = [ extendHostSchema ];
}
