# A key defined once from a bare parametric aspect (a __fn/__args wrapper) and
# once from a nested aspect key (a content wrapper holding a function).
# providerType.merge's parametric branch coerces the wrapper's __fn to includes
# but concatenates the other definitions raw.
{ denTest, ... }:
{
  flake.tests.deadbugs.parametric-wrapper-beside-content-wrapper = {

    # One function inside the content wrapper.
    test-wrapper-plus-single-fn-content = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # A provides child holding a bare parametric function stays a raw
        # __fn/__args wrapper — `provides` is providerType with no coercion.
        den.aspects.holder._.bare =
          { user, ... }:
          {
            nixos.environment.etc."from-bare".text = user.userName;
          };

        den.aspects.libraries.child =
          { host, ... }:
          {
            nixos.environment.etc."from-child".text = host.hostName;
          };

        imports = [
          { den.aspects.foo = den.aspects.holder._.bare; }
          { den.aspects.foo = den.aspects.libraries.child; }
        ];

        den.aspects.igloo.includes = [ den.aspects.foo ];

        expr = {
          bare = igloo.environment.etc."from-bare".text or "<dropped>";
          child = igloo.environment.etc."from-child".text or "<dropped>";
        };
        expected = {
          bare = "tux";
          child = "igloo";
        };
      }
    );

    # Two functions inside the content wrapper.
    test-wrapper-plus-two-fn-content = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # A provides child holding a bare parametric function stays a raw
        # __fn/__args wrapper — `provides` is providerType with no coercion.
        den.aspects.holder._.bare =
          { user, ... }:
          {
            nixos.environment.etc."from-bare".text = user.userName;
          };

        imports = [
          {
            den.aspects.libraries.child =
              { host, ... }:
              {
                nixos.environment.etc."from-child".text = host.hostName;
              };
          }
          {
            den.aspects.libraries.child =
              { user, ... }:
              {
                nixos.environment.etc."from-child-2".text = user.userName;
              };
          }
          { den.aspects.foo = den.aspects.holder._.bare; }
          { den.aspects.foo = den.aspects.libraries.child; }
        ];

        den.aspects.igloo.includes = [ den.aspects.foo ];

        expr = {
          bare = igloo.environment.etc."from-bare".text or "<dropped>";
          child = igloo.environment.etc."from-child".text or "<dropped>";
          child2 = igloo.environment.etc."from-child-2".text or "<dropped>";
        };
        expected = {
          bare = "tux";
          child = "igloo";
          child2 = "tux";
        };
      }
    );

  };
}
