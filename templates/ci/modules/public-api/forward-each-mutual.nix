# Regression test for #567: class forwarder with `each` breaks when
# imported from mutual provider aspect.
{ denTest, ... }:
{
  flake.tests.forward-each-mutual = {

    test-forward-each-from-provide = denTest (
      {
        den,
        lib,
        igloo,
        tuxHm,
        ...
      }:
      let
        nixClass =
          { class, aspect-chain, ... }:
          den._.forward {
            each = [
              "nixos"
              "homeManager"
            ];
            fromClass = _: "nix";
            intoClass = lib.id;
            intoPath = _: [ "nix" ];
            fromAspect = _: lib.head aspect-chain;
            adaptArgs = lib.id;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [ den._.mutual-provider ];

        den.aspects.tux.provides.igloo = {
          includes = [ nixClass ];
          nix.settings.experimental-features = "flakes";
        };

        expr = {
          nixos = igloo.nix.settings.experimental-features;
          hm = tuxHm.nix.settings.experimental-features;
        };
        expected = {
          nixos = "flakes";
          hm = "flakes";
        };
      }
    );

  };
}
