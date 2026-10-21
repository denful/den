# theutz on #682: a quirk producer reached through `den.hosts.<name>.includes`
# yields an empty collection at the consumer, while the same producer reached
# through `den.aspects.<name>.includes` yields its value. Two screenshots, a
# two-byte diff (`hosts` -> `aspects`), same eval:
#
#   den.hosts.kocaeli.includes   = [ rootshell ];  =>  homebrew.taps == [ ]
#   den.aspects.kocaeli.includes = [ rootshell ];  =>  homebrew.taps == [ {...} ]
#
# Distinct from #681: ONE definition of the collection, so nothing is being
# dropped by the registry merge. The reported config is darwin and uses the
# flat `den.hosts.<name>` spelling, neither of which the linux cells cover.
{ denTest, lib, ... }:
{
  flake.tests.deadbugs.quirk-instance-includes-darwin = {

    # CONTROL: the aspect spelling from the second screenshot.
    test-darwin-aspect-includes = denTest (
      { den, apple, ... }:
      {
        den.hosts.aarch64-darwin.apple = { };
        den.quirks.taps.description = "homebrew taps";

        den.aspects.rootshell.taps = [ "kitknox/rootshell" ];
        den.aspects.apple = {
          includes = [ den.aspects.rootshell ];
          darwin =
            {
              taps ? [ ],
              ...
            }:
            {
              environment.etc."taps".text = lib.concatStringsSep "," (lib.flatten taps);
            };
        };

        expr = apple.environment.etc."taps".text or "<dropped>";
        expected = "kitknox/rootshell";
      }
    );

    # The reported case, two-level spelling.
    test-darwin-instance-includes = denTest (
      { den, apple, ... }:
      {
        den.quirks.taps.description = "homebrew taps";

        den.aspects.rootshell.taps = [ "kitknox/rootshell" ];
        den.aspects.apple.darwin =
          {
            taps ? [ ],
            ...
          }:
          {
            environment.etc."taps".text = lib.concatStringsSep "," (lib.flatten taps);
          };

        den.hosts.aarch64-darwin.apple.includes = [ den.aspects.rootshell ];

        expr = apple.environment.etc."taps".text or "<dropped>";
        expected = "kitknox/rootshell";
      }
    );

    # The reported case verbatim: flat spelling, and the host declared in one
    # module with the collection added from another, as in the screenshots
    # (`kocaeli.nix` declares the host, `rootshell.nix` adds the include).
    test-darwin-flat-instance-includes-split = denTest (
      { den, apple, ... }:
      {
        den.quirks.taps.description = "homebrew taps";

        den.aspects.rootshell.taps = [ "kitknox/rootshell" ];
        den.aspects.apple.darwin =
          {
            taps ? [ ],
            ...
          }:
          {
            environment.etc."taps".text = lib.concatStringsSep "," (lib.flatten taps);
          };

        imports = [
          { den.hosts.apple.system = "aarch64-darwin"; }
          { den.hosts.apple.includes = [ den.aspects.rootshell ]; }
        ];

        expr = apple.environment.etc."taps".text or "<dropped>";
        expected = "kitknox/rootshell";
      }
    );

  };
}
