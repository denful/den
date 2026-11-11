# A class key defined more than once, with a definition requiring an entity
# kind, emits one module per definition (userless-host-class-fan.nix). The
# readers of a module's aspect identity still see the aspect: pipe.to targets
# it. Reported in Matrix.
{ denTest, lib, ... }:
let
  transition.den.internal.transitionDefaults = lib.mkForce true;
  pipeBase =
    { den, ... }:
    {
      imports = [ transition ];
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.quirks.secrets.description = "Secret paths";
      den.policies.app-secrets =
        { host, ... }:
        let
          inherit (den.lib.policy) pipe;
        in
        [
          (pipe.from "secrets" [
            (pipe.filter (_: false))
            (pipe.append "pg")
            (pipe.to [ den.aspects.consumer ])
          ])
        ];
      den.default.includes = [ den.policies.app-secrets ];
    };
  # A second definition of `consumer.nixos`.
  secondDef.den.aspects.consumer.nixos.networking.domain = "d";
  userFn =
    { user, secrets, ... }:
    {
      networking.hostName = "${lib.concatStringsSep "+" secrets}-${user.name}";
    };
  hostFn =
    { host, secrets, ... }:
    {
      networking.hostName = "${lib.concatStringsSep "+" secrets}-${host.name}";
    };
in
{
  flake.tests.c1.userless-host-class-fan-readers = {

    test-pipe-to-user-scope-two-definitions = denTest (
      { den, igloo, ... }:
      {
        imports = [
          pipeBase
          secondDef
        ];
        den.aspects.tux.includes = [ den.aspects.consumer ];
        den.aspects.consumer.nixos = userFn;
        expr = igloo.networking.hostName;
        expected = "pg-tux";
      }
    );
    test-pipe-to-host-scope-two-definitions = denTest (
      { den, igloo, ... }:
      {
        imports = [
          pipeBase
          secondDef
        ];
        den.aspects.igloo.includes = [ den.aspects.consumer ];
        den.aspects.consumer.nixos = hostFn;
        expr = igloo.networking.hostName;
        expected = "pg-igloo";
      }
    );
    test-pipe-to-host-fan-two-definitions = denTest (
      { den, igloo, ... }:
      {
        imports = [
          pipeBase
          secondDef
        ];
        den.aspects.igloo.includes = [ den.aspects.consumer ];
        den.aspects.consumer.nixos = userFn;
        expr = igloo.networking.hostName;
        expected = "pg-tux";
      }
    );
    test-pipe-to-host-fan-one-definition = denTest (
      { den, igloo, ... }:
      {
        imports = [ pipeBase ];
        den.aspects.igloo.includes = [ den.aspects.consumer ];
        den.aspects.consumer.nixos = userFn;
        expr = igloo.networking.hostName;
        expected = "pg-tux";
      }
    );

  };
}
