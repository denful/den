{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.fx-integration = {

    # Real den aspect resolves through fx pipeline.
    test-real-aspect-through-fx = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos =
          { ... }:
          {
            networking.hostName = "fx-test";
          };
        expr = igloo.networking.hostName;
        expected = "fx-test";
      }
    );

    # Parametric aspect through fx pipeline.
    test-parametric-through-fx = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.web =
          { host, ... }:
          {
            nixos =
              { ... }:
              {
                networking.hostName = host.name;
              };
          };
        den.aspects.igloo.includes = [ den.aspects.web ];
        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

  };
}
