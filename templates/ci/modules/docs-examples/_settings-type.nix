# Copy of the generator in docs/src/content/docs/guides/aspect-settings.mdx (step 2).
{ den, lib }:
let
  inherit (lib) mkOption types;
  inherit (den.lib.aspects.fx.keyClassification) isStructuralKey;

  # Inside an aspect, keys named after a registered class or quirk are that
  # class's or quirk's data, never child aspects. This doesn't apply at the
  # root: the keys of den.aspects are always aspect names.
  reserved = k: (den.classes or { }) ? ${k} || (den.quirks or { }) ? ${k};
  skipKey = isRoot: k: isStructuralKey k || (!isRoot && reserved k);

  # A reserved key whose `settings` holds real option declarations is an aspect
  # named like a class or quirk: its settings would otherwise vanish, with only a
  # "does not exist" error at the definition.
  hasOptions =
    v:
    builtins.isAttrs v && (v._type or null == "option" || lib.any hasOptions (builtins.attrValues v));
  collides =
    isRoot: k: v:
    !isRoot && reserved k && builtins.isAttrs v && hasOptions (v.settings or { });

  # `settings` is either a bare attrset of options, or a module with
  # options / config / imports.
  reshape = raw: if raw ? options || raw ? config || raw ? imports then raw else { options = raw; };

  hasSettingsDeep =
    isRoot: node:
    builtins.isAttrs node
    && (
      node ? settings
      || lib.any (
        k:
        let
          v = node.${k} or null;
        in
        (!(skipKey isRoot k) && hasSettingsDeep false v) || collides isRoot k v
      ) (builtins.attrNames node)
    );

  # One submodule per aspect-tree node. A node can carry its own settings
  # and also be the parent of aspects that do.
  nodeModule =
    path: node:
    let
      isRoot = path == [ ];
      own = reshape (node.settings or { });
      children = lib.filterAttrs (
        k: v: (!(skipKey isRoot k) && builtins.isAttrs v && hasSettingsDeep false v) || collides isRoot k v
      ) node;
    in
    {
      imports = own.imports or [ ];
      config = own.config or { };
      options =
        (own.options or { })
        // lib.mapAttrs (
          name: child:
          if collides isRoot name child then
            throw "den settings: aspect `${
              lib.concatStringsSep "." (path ++ [ name ])
            }` declares settings, but `${name}` is a registered ${
              if (den.quirks or { }) ? ${name} then "quirk" else "class"
            }, so den reads it as that data and its settings would be dropped. Rename the aspect or the ${
              if (den.quirks or { }) ? ${name} then "quirk" else "class"
            }."
          else
            mkOption {
              type = types.submodule (nodeModule (path ++ [ name ]) child);
              default = { };
              description = "Settings under ${name}";
            }
        ) children;
    };
in
types.submodule (nodeModule [ ] (den.aspects or { }))
