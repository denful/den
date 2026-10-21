# mkParametricBase (nix/lib/aspects/fx/aspect.nix) rebuilt a parametric-resolved
# aspect from an explicit carry-forward whitelist (name, meta, into, provides,
# __walkStamped) instead of merging structural keys onto the original, so a
# sibling `includes` declared alongside a functor-shaped aspect body — already
# preserved through normalize.nix's wrapFunctorChild — was silently dropped the
# moment the aspect went through parametric resolution. No existing cell pinned
# this; it was only found by survey.
{ denTest, ... }:
{
  flake.tests.deadbugs.parametric-sibling-includes = {

    test-parametric-sibling-includes-survive-resolution = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.marker.nixos.networking.hostName = "marker-fired";

        # A single functor-shaped definition: __fn/__args come from __functor,
        # `includes` sits as a sibling key on the same attrset rather than
        # inside the function's returned value.
        den.aspects.foo = {
          __functor = _self: { host, ... }: { };
          includes = [ den.aspects.marker ];
        };

        den.aspects.igloo.includes = [ den.aspects.foo ];

        expr = igloo.networking.hostName;
        expected = "marker-fired";
      }
    );

  };
}
