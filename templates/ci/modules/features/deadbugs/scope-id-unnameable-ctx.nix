# theutz on #682: a quirk reached through `den.hosts.<name>.includes` arrived
# empty while the same aspect through `den.aspects.<name>.includes` delivered.
#
# Cause: `mkScopeId` built the scope IDENTITY from every ctx key, including ones
# whose value it cannot name. Those render as a bare type placeholder
# (`den=<set:den>`, `inputs=<set:inputs>`, `lib=<set:lib>`) — measured on his
# host, where the user scope pushed ctx keys `den|host|inputs|lib|system|user`.
#
# A value that can only render as its own type distinguishes nothing, so it adds
# no identity; all it does is split one logical scope across two ids depending on
# which module args happened to be bound on the path. Pipe emits are bucketed by
# scope id and a consumer reads its own bucket, so producer and consumer landed
# in different buckets and the collection came back empty.
{ denTest, ... }:
{
  flake.tests.deadbugs.scope-id-unnameable-ctx = {

    # An unnameable ctx value must not enter the scope identity.
    test-unnameable-ctx-excluded-from-scope-id = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = den.lib.aspects.fx.pipeline.mkScopeId {
          host = {
            name = "igloo";
          };
          user = {
            name = "tux";
          };
          lib = {
            genAttrs = "not a name";
          };
          inputs = {
            nixpkgs = "not a name";
          };
        };
        expected = "host=igloo,user=tux";
      }
    );

    # CONTROL: nameable coordinates all survive, so the cell above measures the
    # exclusion rather than a scope id that dropped everything.
    test-nameable-ctx-kept-in-scope-id = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = den.lib.aspects.fx.pipeline.mkScopeId {
          host = {
            name = "igloo";
          };
          user = {
            __scopeName = "tux@igloo";
            name = "tux";
          };
          system = "x86_64-linux";
        };
        expected = "host=igloo,system=x86_64-linux,user=tux@igloo";
      }
    );

  };
}
