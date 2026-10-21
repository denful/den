# Follow-up to the report behind #681: is quirk collection entrypoint-agnostic,
# or does a quirk reached through `den.hosts.<sys>.<name>.includes` behave
# differently from one reached through `den.aspects.<name>.includes`?
#
# It is agnostic. Both spellings land in the same `host=<name>` scope
# (`resolve-entity.nix` folds the instance's collection into the entity root
# aspect), so the pipe effects share a bucket. #681's merge defect was the only
# divergence and it was not quirk-specific: the instance registry dropped one
# of two list definitions whatever the list carried.
#
# Every cell pairs an instance spelling with its aspect control, so a future
# divergence shows up as one arm going red rather than as both.
{ denTest, lib, ... }:
{
  flake.tests.deadbugs.quirk-via-instance-includes = {

    # CONTROL: the aspect spelling — documented working path.
    test-via-aspect-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.persist.description = "Paths to persist";

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];
        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        den.aspects.igloo.includes = [
          den.aspects.libraries.producer
          den.aspects.libraries.consumer
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # The reported case: same producer/consumer, included at the instance.
    test-via-host-instance-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.persist.description = "Paths to persist";

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];
        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        den.hosts.x86_64-linux.igloo.includes = [
          den.aspects.libraries.producer
          den.aspects.libraries.consumer
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # Flat host spelling (preprocessHosts groups it by `system`).
    test-via-flat-host-instance-includes = denTest (
      { den, igloo, ... }:
      {
        den.quirks.persist.description = "Paths to persist";

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];
        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        den.hosts.igloo = {
          system = "x86_64-linux";
          users.tux = { };
          includes = [
            den.aspects.libraries.producer
            den.aspects.libraries.consumer
          ];
        };

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # Producer at the instance, consumer on the host aspect.
    test-instance-producer-aspect-consumer = denTest (
      { den, igloo, ... }:
      {
        den.quirks.persist.description = "Paths to persist";

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];

        den.aspects.igloo.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          includes = [ den.aspects.libraries.producer ];
        };

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # Producer on the host aspect, consumer at the instance.
    test-aspect-producer-instance-consumer = denTest (
      { den, igloo, ... }:
      {
        den.quirks.persist.description = "Paths to persist";

        den.aspects.igloo.persist.directories = [ "/var/lib/alpha" ];

        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          includes = [ den.aspects.libraries.consumer ];
        };

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # Instance-included producer feeding a pipe policy.
    test-instance-producer-pipe-policy = denTest (
      { den, igloo, ... }:
      {
        den.quirks.firewall.description = "Firewall ports";

        den.aspects.libraries.producer.firewall = [
          {
            port = 80;
            proto = "tcp";
          }
          {
            port = 53;
            proto = "udp";
          }
        ];

        den.aspects.libraries.consumer.nixos =
          { firewall, ... }:
          {
            networking.hostName = lib.concatMapStringsSep "-" (f: toString f.port) firewall;
          };

        den.policies.filter-tcp =
          { host, ... }:
          [ (den.lib.policy.pipe.from "firewall" [ (den.lib.policy.pipe.filter (e: e.proto == "tcp")) ]) ];

        den.default.includes = [ den.policies.filter-tcp ];

        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          includes = [
            den.aspects.libraries.producer
            den.aspects.libraries.consumer
          ];
        };

        expr = igloo.networking.hostName;
        expected = "80";
      }
    );

    # User instance includes carrying the producer for that user's own consumer.
    test-user-instance-includes = denTest (
      { den, tuxHm, ... }:
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.quirks.hmvals.description = "hm values";

        den.aspects.libraries.producer.hmvals = [ "u" ];
        den.aspects.libraries.consumer.homeManager =
          {
            hmvals ? [ ],
            ...
          }:
          {
            home.sessionVariables.MARKER = lib.concatStringsSep "-" hmvals;
          };

        den.hosts.x86_64-linux.igloo.users.tux.includes = [
          den.aspects.libraries.producer
          den.aspects.libraries.consumer
        ];

        expr = tuxHm.home.sessionVariables.MARKER or "<dropped>";
        expected = "u";
      }
    );

    # The #681 merge, carrying a quirk rather than class content: both
    # definitions must survive for the producer to reach the consumer.
    test-instance-includes-two-definitions = denTest (
      { den, igloo, ... }:
      {
        den.quirks.persist.description = "Paths to persist";

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];
        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        imports = [
          { den.hosts.x86_64-linux.igloo.users.tux = { }; }
          { den.hosts.x86_64-linux.igloo.includes = [ den.aspects.libraries.producer ]; }
          { den.hosts.x86_64-linux.igloo.includes = [ den.aspects.libraries.consumer ]; }
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # CONTROL: the same two-module split on the host ASPECT.
    test-aspect-includes-two-definitions = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.persist.description = "Paths to persist";

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];
        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        imports = [
          { den.aspects.igloo.includes = [ den.aspects.libraries.producer ]; }
          { den.aspects.igloo.includes = [ den.aspects.libraries.consumer ]; }
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # A flat host may declare `system` in one module and content in another:
    # definitions are normalized individually, so the grouping key is gathered
    # across all of them first.
    test-flat-host-system-and-content-split = denTest (
      { den, igloo, ... }:
      {
        den.quirks.persist.description = "Paths to persist";

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];
        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        imports = [
          {
            den.hosts.igloo = {
              system = "x86_64-linux";
              users.tux = { };
            };
          }
          { den.hosts.igloo.includes = [ den.aspects.libraries.producer ]; }
          { den.hosts.igloo.includes = [ den.aspects.libraries.consumer ]; }
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

  };
}
