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

  den.policies.host-to-microvm-host =
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

  den.policies.microvm-host-to-microvm-guest =
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
  # Guest VM policy: resolve VM host externally (isolated pipeline) and
  # deliver its modules to the server via policy.provide at the correct paths.
  # External resolution prevents VM modules from merging into the server's
  # top-level output — only the routed content reaches the server.
  den.policies.microvm-guest-resolve-vm =
    {
      host,
      vm,
      ...
    }:
    let
      inherit (den.lib.policy) provide;

      sharedNixStore = lib.optional host.microvm.sharedNixStore (provide {
        class = host.class;
        path = [
          "microvm"
          "vms"
          vm.name
          "config"
          "microvm"
          "shares"
        ];
        module = [
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
        ];
      });

      # Resolve VM as an isolated host pipeline — its modules stay external.
      vmResolved = den.lib.aspects.resolve vm.class (den.lib.resolveEntity "host" { host = vm; });
      microvmResolved = den.lib.aspects.resolve "microvm" vm.aspect;

      # Deliver VM's OS class modules to server at microvm.vms.<name>.config
      # Use submodule definition form (_: { imports }) so the module system
      # evaluates them within the submodule context.
      osProvide = provide {
        class = host.class;
        path = [
          "microvm"
          "vms"
          vm.name
          "config"
        ];
        module = _: vmResolved;
      };

      # Deliver VM's microvm class modules to server at microvm.vms.<name>
      microvmProvide = provide {
        class = host.class;
        path = [
          "microvm"
          "vms"
          vm.name
        ];
        module = _: microvmResolved;
      };
    in
    [
      osProvide
      microvmProvide
    ]
    ++ sharedNixStore;

  den.schema.host.includes = [ den.policies.host-to-microvm-host ];
  den.schema.microvm-host.includes = [ den.policies.microvm-host-to-microvm-guest ];
  den.schema.microvm-guest.includes = [ den.policies.microvm-guest-resolve-vm ];
  den.schema.host.imports = [ extendHostSchema ];
}
