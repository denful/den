# Issue #448: attribute 'host' missing when a sub-aspect is defined across
# multiple modules that mix bare parametric functions with plain attrsets.
#
# Root cause: providerType's either merge fell back to aspectType.merge
# for mixed defs, which evaluated the parametric function as a NixOS module
# (wrong context — host isn't in _module.args).
{ denTest, ... }:
{
  flake.tests.deadbugs-issue-448 = {

    # Mixed function + attrset at same sub-aspect path.
    test-mixed-merge-fx = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.bar._.sub =
              { host, ... }:
              {
                nixos.networking.hostName = host.hostName;
              };
          }
          {
            den.aspects.bar._.sub.nixos.programs.vim.enable = true;
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.bar._.sub ];

        expr = {
          hostname = igloo.networking.hostName;
          vim = igloo.programs.vim.enable;
        };
        expected = {
          hostname = "igloo";
          vim = true;
        };
      }
    );

    # Same on legacy pipeline.
    test-mixed-merge-legacy = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          {
            den.aspects.bar._.sub =
              { host, ... }:
              {
                nixos.networking.hostName = host.hostName;
              };
          }
          {
            den.aspects.bar._.sub.nixos.programs.vim.enable = true;
          }
        ];

        den.aspects.igloo.includes = [ den.aspects.bar._.sub ];

        expr = {
          hostname = igloo.networking.hostName;
          vim = igloo.programs.vim.enable;
        };
        expected = {
          hostname = "igloo";
          vim = true;
        };
      }
    );

  };
}
