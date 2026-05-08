# See https://github.com/denful/den/discussions/317
let
  message = ''
    If you see this message it likely means you have more than
    one value for a flake output that was expected to be unique.

    This means no flake.* option was defined for that attribute,
    and the Nix module system does not know how to merge both values.

    For example, if error relates to `flake.nixosConfigurations`
    output, you can import the following at top-level:

      ```nix
      # modules/den.nix
      { inputs, ... }:
      {
        imports = [ inputs.den.flakeOutputs.nixosConfigurations ];
      }
      ```

    Same applies to `homeConfigurations`, `packages`, or any other 
    flake output attribute that might need merge-semantics for
    multiple values.

    If you desire to define the merge strategy yourself,
    Add the following in your project, create a module like:

      ```nix
      # modules/output.nix
      { lib, ... }: {
        options.flake.nixosConfigurations = lib.mkOption {
          default = { };
          type = lib.types.lazyAttrsOf lib.types.raw;
        };
      }
      ```

    See also flake-parts related error messaage: 
    https://github.com/hercules-ci/flake-parts/blob/main/modules/flake.nix
  '';

  flakeNames = [
    "nixosConfigurations"
    "darwinConfigurations"
    "homeConfigurations"
  ];

  systemNames = [
    "devShells"
    "packages"
    "apps"
    "checks"
    "tests"
    "legacyPackages"
  ];

  uniqueSubmodule =
    lib:
    lib.types.submodule {
      freeformType = lib.types.lazyAttrsOf (lib.types.unique { inherit message; } lib.types.raw);
    };

  manySubmodule =
    lib: imports:
    lib.types.submodule {
      inherit imports;

      freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
    };

  systemOut =
    lib:
    lib.mkOption {
      default = { };
      defaultText = lib.literalExpression "{ }";
      type = lib.types.lazyAttrsOf (manySubmodule lib [ ]);
    };

  flakeOut =
    lib:
    lib.mkOption {
      default = { };
      defaultText = lib.literalExpression "{ }";
      type = (manySubmodule lib [ ]);
    };

  flakeTop =
    { lib, den }:
    lib.mkOption {
      default = { };
      defaultText = lib.literalExpression "{ }";
      type = (manySubmodule lib [ (den.schema.flake or { }) ]);
    };

  flakeBased = builtins.listToAttrs (
    map (name: {
      inherit name;
      value =
        { lib, ... }:
        {
          options.flake.${name} = flakeOut lib;
        };
    }) flakeNames
  );

  systemBased = builtins.listToAttrs (
    map (name: {
      inherit name;
      value =
        { lib, ... }:
        {
          options.flake.${name} = systemOut lib;
        };
    }) systemNames
  );

  all.includes = builtins.attrValues (flakeBased // systemBased);

  flake =
    { lib, config, ... }:
    {
      options.flake = flakeTop {
        inherit lib;
        den = config.den or { };
      };
    };

in
flakeBased
// systemBased
// {
  inherit flake all;
}
