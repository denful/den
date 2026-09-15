{ denTest, ... }:
let
  # One fixture, five arms, read through distinct TCP ports so every arm is a
  # boolean presence test rather than a diff-renderer read.
  fixture = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.firewall.description = "Firewall port declarations";

    den.aspects.igloo = {
      firewall.ports = [ 22 ];
      includes = [
        # ARM 1 (control) — plain aspect-level include, nested includes.
        den.aspects.plain-parent

        # ARM 2 (D1) — pipe-arg deferred aspect-level include, nested includes.
        (
          { firewall, ... }:
          {
            name = "d1-deferred-parent";
            includes = [ den.aspects.deferred-leaf ];
          }
        )

        # ARM 3 — pipe-arg deferred aspect-level include, DIRECT class content.
        (
          { firewall, ... }:
          {
            name = "d1-deferred-direct";
            nixos.networking.firewall.allowedTCPPorts = [ 10030 ];
          }
        )

        # ARM 4 — aspect-level include that IS a function but binds
        # synchronously (host is in scope ctx), nested includes.
        (
          { host, ... }:
          {
            name = "d1-sync-fn-parent";
            includes = [ den.aspects.sync-fn-leaf ];
          }
        )

        # ARM 5 — pipe-arg deferred aspect-level include, NESTED aspect key.
        # NOT a D1 instance: a nested aspect key never auto-walks, deferred
        # or not (compile-static.nix's own comment says so). Paired below
        # with ARM 5B, its non-deferred twin, as an invariance cell — both
        # must read false, and a future change that starts auto-walking
        # nested keys flips both together.
        (
          { firewall, ... }:
          {
            name = "d1-deferred-nestedkey";
            sub.nixos.networking.firewall.allowedTCPPorts = [ 10050 ];
          }
        )

        # ARM 5B — plain (non-deferred) aspect-level include, NESTED aspect
        # key. The invariance twin of ARM 5.
        {
          name = "plain-nestedkey-parent";
          sub.nixos.networking.firewall.allowedTCPPorts = [ 10060 ];
        }
      ];
    };

    den.aspects.plain-parent.includes = [ den.aspects.plain-leaf ];
    den.aspects.plain-leaf.nixos.networking.firewall.allowedTCPPorts = [ 10010 ];
    den.aspects.deferred-leaf.nixos.networking.firewall.allowedTCPPorts = [ 10020 ];
    den.aspects.sync-fn-leaf.nixos.networking.firewall.allowedTCPPorts = [ 10040 ];
  };

  arm =
    port:
    denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = builtins.elem port igloo.networking.firewall.allowedTCPPorts;
        expected = true;
      }
    );

  # Invariance cells: the port must NEVER appear (nested keys never
  # auto-walk), as opposed to the negative control below (a port nothing
  # declares at all).
  armFalse =
    port:
    denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = builtins.elem port igloo.networking.firewall.allowedTCPPorts;
        expected = false;
      }
    );
in
{
  flake.tests.d1probe = {
    test-arm1-control-plain-nested = arm 10010;
    test-arm2-deferred-nested-includes = arm 10020;
    test-arm3-deferred-direct-class = arm 10030;
    test-arm4-syncfn-nested-includes = arm 10040;
    test-arm5-deferred-nested-key = armFalse 10050;
    test-arm5b-plain-nestedkey-invariance = armFalse 10060;

    # Negative control: a port nothing declares must read absent, proving the
    # predicate is not stuck at true.
    test-negcontrol-undeclared-port = denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = builtins.elem 19999 igloo.networking.firewall.allowedTCPPorts;
        expected = false;
      }
    );
  };
}
