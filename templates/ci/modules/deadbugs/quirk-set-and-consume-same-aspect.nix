# User report (second claim): setting a quirk value in the SAME aspect that
# consumes the quirk silently drops the value. Setting it from a different
# aspect works.
{ denTest, lib, ... }:
{
  flake.tests.deadbugs.quirk-set-and-consume-same-aspect = {

    # FAILING: producer and consumer are the same aspect.
    test-same-aspect-set-and-consume = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.persist = {
          description = "Paths to persist";
        };

        den.aspects.libraries.alpha = {
          persist.directories = [ "/var/lib/alpha" ];
          nixos =
            { persist, ... }:
            {
              environment.etc."persisted".text = lib.concatStringsSep "," (
                lib.concatMap (p: p.directories or [ ]) persist
              );
            };
        };

        den.aspects.igloo.includes = [ den.aspects.libraries.alpha ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # CONTROL: producer is a separate aspect — the documented working path.
    test-separate-aspect-set-and-consume = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.persist = {
          description = "Paths to persist";
        };

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/alpha" ];

        den.aspects.libraries.alpha.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        den.aspects.igloo.includes = [
          den.aspects.libraries.producer
          den.aspects.libraries.alpha
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

    # Both: same aspect sets its own value AND a sibling contributes.
    test-same-aspect-plus-sibling = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.persist = {
          description = "Paths to persist";
        };

        den.aspects.libraries.producer.persist.directories = [ "/var/lib/producer" ];

        den.aspects.libraries.alpha = {
          persist.directories = [ "/var/lib/alpha" ];
          nixos =
            { persist, ... }:
            {
              environment.etc."persisted".text = lib.concatStringsSep "," (
                lib.sort (a: b: a < b) (lib.concatMap (p: p.directories or [ ]) persist)
              );
            };
        };

        den.aspects.igloo.includes = [
          den.aspects.libraries.producer
          den.aspects.libraries.alpha
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha,/var/lib/producer";
      }
    );

    # The reporter's quirk symptom, predicted to be the same defect as
    # samename-mixed-merge-drop: the aspect has a parametric definition
    # alongside a static one, and the static one carries the quirk value.
    test-quirk-value-in-static-def-beside-parametric-def = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.persist = {
          description = "Paths to persist";
        };

        imports = [
          {
            den.aspects.libraries.alpha =
              { host, ... }:
              {
                nixos.environment.etc."hostname-marker".text = host.hostName;
              };
          }
          {
            den.aspects.libraries.alpha.persist.directories = [ "/var/lib/alpha" ];
          }
        ];

        den.aspects.libraries.consumer.nixos =
          { persist, ... }:
          {
            environment.etc."persisted".text = lib.concatStringsSep "," (
              lib.concatMap (p: p.directories or [ ]) persist
            );
          };

        den.aspects.igloo.includes = [
          den.aspects.libraries.alpha
          den.aspects.libraries.consumer
        ];

        expr = igloo.environment.etc."persisted".text or "<dropped>";
        expected = "/var/lib/alpha";
      }
    );

  };
}
