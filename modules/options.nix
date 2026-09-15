{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (config) den;
  types = import ./../nix/lib/types.nix {
    inherit
      inputs
      lib
      den
      config
      ;
  };
  # Imported directly, not via den.lib.schema: this declares options.den.schema,
  # and den.lib's map includes schema-util which reads den.schema._kindNames —
  # routing through den.lib here would close that cycle. Entity types consume it
  # lazily at eval time, so they safely use den.lib.schema.
  schemaLib = import ./../nix/lib/schema.nix { inherit inputs lib; };

  # Element check for BOTH schema-tier collections. gen-schema has no
  # per-collection `type` to route a bad element through, so the check that the
  # aspect tier gets from `providerType` has to live here — and it has to be
  # ONE check: the two collections take the same references, so a shape that
  # excludes at the aspect tier must not throw at the schema tier.
  #
  # A bare string was the original defect at both. Unchecked, it reached
  # children.nix's aspect walk and crashed with a raw Nix `expected a set but
  # found a string` from propagateScope's `//` on the includes side, and on the
  # excludes side `identity.key` reduced it to "<anon>", which matches no
  # policy and so excluded nothing in silence.
  #
  # Recurses into nested lists because `providerType` names a list of policy
  # records as a valid element and children.nix walks nested lists the same way
  # at both tiers (`processInclude`, and `lib.flatten` over excludes since
  # 6127cbc). Admits a function because a parametric aspect reference is one.
  checkCollectionElement =
    collection:
    let
      check =
        v:
        if builtins.isList v then
          map check v
        else if builtins.isAttrs v || lib.isFunction v then
          v
        else
          throw "den: den.schema.<kind>.${collection}: expected a policy or aspect reference, got ${
            if builtins.isString v then ''"${v}"'' else builtins.typeOf v
          }";
    in
    check;

  classSchemaType = lib.types.submodule (
    { ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this class domain.";
        type = lib.types.str;
      };
      options.forwardTo = lib.mkOption {
        description = "Optional forward target for class evaluation.";
        type = lib.types.nullOr lib.types.raw;
        default = null;
      };
      options.parentPath = lib.mkOption {
        description = ''
          For a class whose members nest inside an enclosing config-owner (e.g.
          home-manager inside a host), a function `name -> path` locating a named
          member within that owner's config — the same route the class's content
          is delivered to. The pipe layer uses it to resolve a producer's config
          at its producing class + scope. null for root classes that own a
          top-level config (nixos, darwin, terranix, …).
        '';
        type = lib.types.nullOr lib.types.raw;
        default = null;
      };
      options.parentArg = lib.mkOption {
        description = ''
          For a nested class, the module argument by which a member reaches the
          enclosing config-owner (home-manager exposes the host config as
          `osConfig`). The pipe layer hands a deferred config-thunk the owner
          config under this name. null for root classes.
        '';
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    }
  );

  pipeSchemaType = lib.types.submodule (
    { ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this pipe.";
        type = lib.types.str;
      };
    }
  );
in
{
  options.den.hosts = types.hostsOption;
  options.den.homes = types.homesOption;
  options.den.schema = schemaLib.mkSchemaOption {
    collections = {
      includes = {
        default = [ ];
        merge = acc: val: acc ++ map (checkCollectionElement "includes") val;
      };
      excludes = {
        default = [ ];
        merge = acc: val: acc ++ map (checkCollectionElement "excludes") val;
      };
      isEntity = {
        default = false;
        merge = acc: val: acc || val;
      };
      isolated = {
        default = false;
        merge = acc: val: acc || val;
      };
    };
    computed = collections: defs: {
      isEntity =
        collections.isEntity
        || builtins.any (
          d:
          let
            v = d.value;
            collectionKeys = [
              "includes"
              "excludes"
              "isEntity"
              "isolated"
              "parent"
              "collisionPolicy"
            ];
            stripped = if builtins.isAttrs v then builtins.removeAttrs v collectionKeys else v;
          in
          !builtins.isAttrs stripped || stripped != { }
        ) defs;
    };
  };
  # Built-in entity topology: users nest inside hosts, homes nest inside hosts.
  config.den.schema.user.parent = "host";
  config.den.schema.home.parent = "host";

  options.den.reservedKeys = lib.mkOption {
    description = "Additional aspect keys reserved from pipeline dispatch. These keys are treated as structural — the pipeline ignores them, letting consumers use them for metadata.";
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [
      "settings"
      "tags"
    ];
  };

  options.den.classes = lib.mkOption {
    description = "Class evaluation domains";
    type = lib.types.lazyAttrsOf classSchemaType;
    default = { };
  };
  options.den.quirks = lib.mkOption {
    description = "Quirk declarations — named data routes for structured quirk flow";
    type = lib.types.lazyAttrsOf pipeSchemaType;
    default = { };
    apply =
      quirks:
      let
        classKeys = builtins.attrNames (den.classes or { });
        overlap = builtins.filter (k: builtins.elem k classKeys) (builtins.attrNames quirks);
      in
      assert
        overlap == [ ]
        || throw "den.classes and den.quirks must not share keys, but found: ${builtins.concatStringsSep ", " overlap}";
      lib.mapAttrs (name: v: v // { inherit name; }) quirks;
  };
  config.den.schema.conf = { };
  config.den.schema.fleet = { };
  config.den.schema.host.imports = [ den.schema.conf ];
  config.den.schema.user.imports = [ den.schema.conf ];
  # `home`'s identity keys are declared AT THE KIND, not on the instance.
  # gen-schema closes the identity-key set the moment the kind is a value, so
  # an option contributed through `mkInstanceType`'s `extraModules` cannot be
  # an identity key, and the reflected set drops `internal` options outright.
  # Naming either from `_identity.keys` is a hard error rather than the silent
  # success it used to be.
  #
  # home is the only kind that needs its own keys: `name` is forced to the bare
  # user name so `den.aspects.<user>` resolves, and two `user@host` homes on one
  # system share that name. The registry key and the system are what actually
  # tell them apart. Declared here, defined on the instance — identity is read
  # off declarations, so the per-system value stays where it is computed.
  config.den.schema.home.imports = [
    den.schema.conf
    {
      # `visible = false`, never `internal = true`: gen-schema's
      # `isPrimitiveOption` excludes an `internal` option from the identity set
      # outright, so marking these internal would un-declare the very keys
      # `_identity.keys` names. It reads `internal` and `identity` and NOT
      # `visible`, so this keeps both out of rendered option docs while leaving
      # them identity-eligible.
      options.__scopeName = lib.mkOption {
        type = lib.types.str;
        visible = false;
        description = "Registry key of this home, used as its scope and identity.";
      };
      options.system = lib.mkOption {
        type = lib.types.str;
        visible = false;
        description = "platform system";
      };
    }
  ];
  config.den.classes = {
    nixos.description = "NixOS system configuration";
    darwin.description = "nix-darwin system configuration";
  };
}
