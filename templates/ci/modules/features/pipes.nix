{ denTest, lib, ... }:
{
  flake.tests.pipes = {
    test-pipe-declaration = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.firewall = {
          description = "Firewall port declarations";
        };
        den.aspects.igloo = {
          nixos.networking.hostName = "pipe-test";
        };
        expr = igloo.networking.hostName;
        expected = "pipe-test";
      }
    );

    test-pipe-class-collision = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.pipes.nixos = {
          description = "should collide with den.classes.nixos";
        };
        # Accessing den.pipes should trigger the collision assertion.
        expr = !(builtins.tryEval (builtins.deepSeq den.pipes null)).success;
        expected = true;
      }
    );
  };
}
