# A quirk produced within a user's class context must reach that user's
# homeManager consumer — including when the consumer arrives via the
# host-aspects projection (den.batteries.host-aspects), symmetric with how a
# host's nixos-aspect quirk reaches the host's nixos consumer.
#
# Repro for: a user-scope homeManager quirk emit does not reach a homeManager
# consumer that was projected onto the user via host-aspects. The consumer sees
# only host-scope emits (re-emitted host -> home), never the user's own.
{ denTest, lib, ... }:
{
  flake.tests.user-class-quirk-exposure = {

    # Baseline: host aspect emits a quirk, host's nixos consumer reads it
    # locally — no pipe policy. host <-> nixos works.
    test-host-quirk-local-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.hostvals.description = "host values";

        den.aspects.igloo.includes = [
          den.aspects.host-emitter
          den.aspects.host-consumer
        ];
        den.aspects.host-emitter.hostvals = [ "h" ];
        den.aspects.host-consumer.nixos =
          {
            hostvals ? [ ],
            ...
          }:
          {
            networking.hostName = lib.concatStringsSep "-" hostvals;
          };

        expr = igloo.networking.hostName;
        expected = "h";
      }
    );

    # Baseline: user aspect emits a quirk, user's OWN homeManager consumer reads
    # it locally — no pipe policy. user <-> homeManager works when both are in
    # the same directly-included user scope.
    test-user-quirk-local-home = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.quirks.hmvals.description = "hm values";

        den.aspects.tux.includes = [
          den.aspects.hm-emitter
          den.aspects.hm-consumer
        ];
        den.aspects.hm-emitter.hmvals = [ "u" ];
        den.aspects.hm-consumer.homeManager =
          {
            hmvals ? [ ],
            ...
          }:
          {
            home.sessionVariables.HMVALS = lib.concatStringsSep "-" hmvals;
          };

        expr = tuxHm.home.sessionVariables.HMVALS or "MISSING";
        expected = "u";
      }
    );

    # THE BUG (minimal nix-config repro). The homeManager consumer reaches the
    # user via den.batteries.host-aspects (users/sini.nix includes it), i.e. the
    # consumer is host-aspects-PROJECTED. A user-scope quirk emit (fenix) must
    # reach that projected consumer. It does not: the consumer reads an empty
    # collection.
    test-user-quirk-into-host-aspects-projected-consumer = denTest (
      { den, tuxHm, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.homeManager.home.stateVersion = "25.11";
        den.quirks.hmvals.description = "hm values";

        # Host aspect's homeManager body IS the consumer, projected to opted-in
        # users via host-aspects (the core.nix.nixpkgs analog).
        den.aspects.igloo.homeManager =
          {
            hmvals ? [ ],
            ...
          }:
          {
            home.sessionVariables.HMVALS = lib.concatStringsSep "-" hmvals;
          };

        # tux opts into the host-aspects projection AND emits a user-scope quirk.
        den.aspects.tux.includes = [
          den.batteries.host-aspects
          den.aspects.user-emitter
        ];
        den.aspects.user-emitter.hmvals = [ "user" ];

        expr = tuxHm.home.sessionVariables.HMVALS or "MISSING";
        expected = "user";
      }
    );

  };
}
