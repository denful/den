# den.reservedKeys lets a config mark extra aspect keys as structural. The
# pipeline skips them (no class/nested/pipe dispatch) and the aspect type
# leaves their values untouched, so consumers can use them for free-form
# metadata and read them back exactly as declared.
{ denTest, ... }:
{
  flake.tests.reserved-keys = {
    # A reserved key carries metadata: the rest of the aspect resolves
    # normally, and the key's value passes through unwrapped. Without
    # reservation `settings` would be dispatched and its value content-wrapped.
    test-reserved-key-is-metadata = denTest (
      { den, igloo, ... }:
      {
        den.reservedKeys = [ "settings" ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo = {
          settings = {
            theme = "dark";
          };
          nixos.networking.hostName = "reserved-test";
        };

        expr = {
          resolves = igloo.networking.hostName;
          metadata = den.aspects.igloo.settings;
        };
        expected = {
          resolves = "reserved-test";
          metadata = {
            theme = "dark";
          };
        };
      }
    );
  };
}
