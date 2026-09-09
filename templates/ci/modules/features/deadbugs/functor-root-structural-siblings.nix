# normalizeRoot (nix/lib/aspects/default.nix) rebuilds a functor-shaped ROOT
# aspect from an explicit whitelist (name, meta, includes, __scopeHandlers),
# dropping every other structural key — excludes, provides, policies, into,
# classes and every `__` marker. A merged aspect only keeps a user-written
# __functor (resolveAspectWith, the synthetic one, is a non-pattern lambda and
# reports no functionArgs), so the branch is reached exactly when such an
# aspect is resolved as a root: `funnyNames den.aspects.<fn-shaped>`.
#
# The control twin pins that this is the whitelist and not `excludes` being
# inert at a funnyNames root.
{ denTest, ... }:
{
  flake.tests.deadbugs.functor-root-structural-siblings = {

    test-functor-root-excludes-survive-normalize = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.frss-dropped.funny.names = [ "dropped" ];
        den.aspects.frss-kept.funny.names = [ "kept" ];

        den.aspects.frss-fnroot = {
          __functor =
            _self:
            {
              host ? null,
              ...
            }:
            { };
          includes = [
            den.aspects.frss-dropped
            den.aspects.frss-kept
          ];
          excludes = [ den.aspects.frss-dropped ];
        };

        expr = funnyNames den.aspects.frss-fnroot;
        expected = [ "kept" ];
      }
    );

    # Control: same shape, no __functor — normalizeRoot passes it through
    # untouched, so `excludes` reaches registerConstraints.
    test-plain-root-excludes-control = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.frss-c-dropped.funny.names = [ "dropped" ];
        den.aspects.frss-c-kept.funny.names = [ "kept" ];

        den.aspects.frss-plainroot = {
          includes = [
            den.aspects.frss-c-dropped
            den.aspects.frss-c-kept
          ];
          excludes = [ den.aspects.frss-c-dropped ];
        };

        expr = funnyNames den.aspects.frss-plainroot;
        expected = [ "kept" ];
      }
    );

  };
}
