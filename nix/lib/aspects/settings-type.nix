# The option type behind `host.settings.<aspect path>`: one submodule per
# aspect-tree node, carrying the options each aspect declares under its
# reserved `settings` key. Attach it to any entity schema.
{ den, lib }:
let
  inherit (lib) mkOption types;
  inherit (import ./fx/key-classification.nix { inherit den lib; }) isStructuralKey;

  # Inside an aspect, keys named after a registered class or quirk are that
  # class's or quirk's data, never child aspects. The keys of den.aspects are
  # always aspect names, so the rule does not apply at the root.
  reserved = k: (den.classes or { }) ? ${k} || (den.quirks or { }) ? ${k};
  reservedKind = k: if (den.quirks or { }) ? ${k} then "quirk" else "class";
  skipKey = isRoot: k: isStructuralKey k || (!isRoot && reserved k);

  # A reserved key whose `settings` holds option declarations is an aspect
  # named like a class or quirk; without this it would vanish silently.
  hasOptions =
    v:
    builtins.isAttrs v && (v._type or null == "option" || lib.any hasOptions (builtins.attrValues v));
  collides =
    isRoot: k: v:
    !isRoot && reserved k && builtins.isAttrs v && hasOptions (v.settings or { });

  # `settings` is either a bare attrset of options, or a module with
  # options / config / imports.
  reshape = raw: if raw ? options || raw ? config || raw ? imports then raw else { options = raw; };

  # Per node, never a whole-tree pass: parts of den.aspects can depend on
  # settings, and an eager walk recurses.
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
            }` declares settings, but `${name}` is a registered ${reservedKind name}, so den reads it as that data and its settings would be dropped. Rename the aspect or the ${reservedKind name}."
          else
            mkOption {
              type = types.submodule (nodeModule (path ++ [ name ]) child);
              default = { };
              description = "Settings under ${name}";
            }
        ) children;
    };
in
if builtins.elem "settings" (den.reservedKeys or [ ]) then
  types.submodule (nodeModule [ ] (den.aspects or { }))
else
  throw ''den settings: `den.lib.aspects.settingsType` reads each aspect's `settings` key, so it must be reserved: add `den.reservedKeys = [ "settings" ];`.''
