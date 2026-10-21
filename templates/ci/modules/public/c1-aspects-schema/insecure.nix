{ denTest, ... }:
{
  flake.tests.insecure = {
    test-insecure-package-set-on-nixos = denTest (
      {
        den,
        igloo,
        pkgs,
        ...
      }:

      let
        hello = (
          pkgs.hello.overrideAttrs {
            version = "1.0.0";
            meta.knownVulnerabilities = [
              "foo"
            ];
          }
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          includes = [ (den.provides.insecure [ "hello-1.0.0" ]) ];
          environment.systemPackages = [ hello ];
        };
        expr = igloo.nixpkgs.config.permittedInsecurePackages;
        expected = [ "hello-1.0.0" ];
      }
    );
  };
}
