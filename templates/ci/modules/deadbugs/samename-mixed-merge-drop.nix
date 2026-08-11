# User report: an aspect declared under the SAME name in two files loses one
# definition's class content when one definition is a parametric function
# (`{ user, ... }: { nixos = ...; }`) and the other a plain attrset
# (`{ nixos = ...; }`). Renaming either definition restores both.
#
# Reporter expects same-name definitions to merge, which they do when both
# definitions have the same shape.
{ denTest, ... }:
{
  flake.tests.deadbugs.samename-mixed-merge-drop = {

    # FAILING: parametric fn + static attrset at the same nested aspect name.
    test-parametric-plus-static-both-emit = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha =
              { user, ... }:
              {
                nixos.environment.etc."from-parametric".text = user.userName;
              };
          }
          {
            den.aspects.libraries.alpha.nixos.environment.etc."from-static".text = "static";
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.libraries.alpha ];

        expr = {
          parametric = igloo.environment.etc."from-parametric".text or "<dropped>";
          static = igloo.environment.etc."from-static".text or "<dropped>";
        };
        expected = {
          parametric = "tux";
          static = "static";
        };
      }
    );

    # Same shape, but the parametric definition's class value is itself a
    # module function — the reporter's exact layering.
    test-parametric-with-class-module-plus-static = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha =
              { user, ... }:
              {
                nixos =
                  { lib, ... }:
                  {
                    environment.etc."from-parametric".text = lib.toUpper user.userName;
                  };
              };
          }
          {
            den.aspects.libraries.alpha.nixos.environment.etc."from-static".text = "static";
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.libraries.alpha ];

        expr = {
          parametric = igloo.environment.etc."from-parametric".text or "<dropped>";
          static = igloo.environment.etc."from-static".text or "<dropped>";
        };
        expected = {
          parametric = "TUX";
          static = "static";
        };
      }
    );

    # CONTROL: parametric definition asks for `host`, not `user`.
    test-parametric-host-arg-plus-static = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha =
              { host, ... }:
              {
                nixos.environment.etc."from-parametric".text = host.hostName;
              };
          }
          {
            den.aspects.libraries.alpha.nixos.environment.etc."from-static".text = "static";
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.libraries.alpha ];

        expr = {
          parametric = igloo.environment.etc."from-parametric".text or "<dropped>";
          static = igloo.environment.etc."from-static".text or "<dropped>";
        };
        expected = {
          parametric = "igloo";
          static = "static";
        };
      }
    );

    # CONTROL: both definitions static — the merge the reporter says works.
    test-static-plus-static-both-emit = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha.nixos.environment.etc."from-a".text = "a";
          }
          {
            den.aspects.libraries.alpha.nixos.environment.etc."from-b".text = "b";
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.libraries.alpha ];

        expr = {
          a = igloo.environment.etc."from-a".text or "<dropped>";
          b = igloo.environment.etc."from-b".text or "<dropped>";
        };
        expected = {
          a = "a";
          b = "b";
        };
      }
    );

    # Blast radius: same mix at a TOP-LEVEL aspect name rather than a nested
    # key, which reaches providerType.merge without a content wrapper.
    test-toplevel-parametric-plus-static = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.alpha =
              { host, ... }:
              {
                nixos.environment.etc."from-parametric".text = host.hostName;
              };
          }
          {
            den.aspects.alpha.nixos.environment.etc."from-static".text = "static";
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.alpha ];

        expr = {
          parametric = igloo.environment.etc."from-parametric".text or "<dropped>";
          static = igloo.environment.etc."from-static".text or "<dropped>";
        };
        expected = {
          parametric = "igloo";
          static = "static";
        };
      }
    );

    # Two parametric definitions plus a static one. This flips which side is
    # lost: the static definition survives and BOTH parametric ones vanish,
    # because the collapse takes its other branch.
    test-two-parametric-plus-static-both-emit = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha =
              { host, ... }:
              {
                nixos.environment.etc."from-parametric".text = host.hostName;
              };
          }
          {
            den.aspects.libraries.alpha =
              { user, ... }:
              {
                nixos.environment.etc."from-parametric-2".text = user.userName;
              };
          }
          {
            den.aspects.libraries.alpha.nixos.environment.etc."from-static".text = "static";
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.libraries.alpha ];

        expr = {
          parametric = igloo.environment.etc."from-parametric".text or "<dropped>";
          parametric2 = igloo.environment.etc."from-parametric-2".text or "<dropped>";
          static = igloo.environment.etc."from-static".text or "<dropped>";
        };
        expected = {
          parametric = "igloo";
          parametric2 = "tux";
          static = "static";
        };
      }
    );

    # CONTROL: the reporter's workaround — distinct names, both included.
    test-distinct-names-both-emit = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.libraries.alpha =
              { user, ... }:
              {
                nixos.environment.etc."from-parametric".text = user.userName;
              };
          }
          {
            den.aspects.libraries.beta.nixos.environment.etc."from-static".text = "static";
          }
        ];

        den.aspects.igloo.includes = [
          den.aspects.libraries.alpha
          den.aspects.libraries.beta
        ];

        expr = {
          parametric = igloo.environment.etc."from-parametric".text or "<dropped>";
          static = igloo.environment.etc."from-static".text or "<dropped>";
        };
        expected = {
          parametric = "tux";
          static = "static";
        };
      }
    );

  };
}
