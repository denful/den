# The structural-key registry (nix/lib/aspects/fx/key-classification.nix) used
# to enumerate its `__`-prefixed half, so a pipeline marker added without an
# entry there was classified as ordinary aspect content — dispatched as a class
# or nested key instead of being handled by the pipeline. The `__` half is a
# rule now; this pins it against a marker name that is deliberately NOT listed.
{ denTest, ... }:
{
  flake.tests.structural-key-rule = {

    test-unlisted-double-underscore-key-is-not-dispatched = denTest (
      { den, ... }:
      let
        # `futureMarker` is the live control: the identical value under a name
        # with no `__` prefix must still classify as a nested key, so a green
        # here cannot come from classifyKeys failing to classify anything.
        cls = den.lib.aspects.fx.keyClassification.classifyKeys null {
          name = "probe";
          meta = { };
          __futureMarker.includes = [ ];
          futureMarker.includes = [ ];
        };
      in
      {
        expr = {
          inherit (cls)
            classKeys
            nestedKeys
            unregisteredClassKeys
            pipeKeys
            ;
        };
        expected = {
          classKeys = [ ];
          nestedKeys = [ "futureMarker" ];
          unregisteredClassKeys = [ ];
          pipeKeys = [ ];
        };
      }
    );

  };
}
