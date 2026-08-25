# Worked examples for `host.hasAspect` and `meta.handleWith` constraints.
#
# Two complementary tools for two different jobs:
#
#   - `entity.hasAspect` READS structure at query time from inside
#     class-config module bodies (`nixos = ...`, `homeManager = ...`).
#     Cycle-safe because the body runs at evalModules time, long after
#     the aspect tree has been resolved and frozen.
#
#   - `meta.handleWith` with `den.lib.aspects.fx.constraints`
#     (exclude / substitute / filterBy) WRITEs structure at resolve time
#     with full structural visibility. The right tool for "prefer A over
#     B when both are present" and other tree-shape decisions.
#
# These illustrative aspects are all `example-` prefixed to make it
# clear they are pedagogical stubs and to avoid colliding with any
# real aspect names in the template.
{ den, lib, ... }:
{

  # ──────────────────────────────────────────────────────────────────
  # Pattern 1 — Reading structure via `host.hasAspect` from a class body
  # ──────────────────────────────────────────────────────────────────
  #
  # The 95% case. A parametric aspect captures `host` from its functor
  # arguments and uses `host.hasAspect` inside its `nixos = ...` body
  # to branch on whether a companion aspect is structurally present on
  # the same host.
  #
  # This is cycle-safe: the `nixos` body is a deferred module that
  # runs during evalModules, by which point `host.resolved` (the
  # aspect tree this query reads) has already been computed and is
  # frozen. There is no back-edge from the body into the tree.

  # Two "backend" aspects an impermanence setup can be flavored against.
  den.aspects.example-zfs-root.nixos = {
    # Stub representing the zfs-root configuration that would set up
    # zpools, datasets, the boot loader, etc. Kept empty here so the
    # example template still evaluates without zfs-specific options.
    environment.etc."example-root-backend".text = "zfs";
  };

  den.aspects.example-btrfs-root.nixos = {
    environment.etc."example-root-backend".text = "btrfs";
  };

  # An impermanence aspect that adapts its config based on which root
  # backend is also present on the host. The outer `{ host, ... }:`
  # makes the aspect parametric, which is what gives the inner `nixos`
  # body access to `host.hasAspect`.
  den.aspects.example-impermanence =
    { host, ... }:
    {
      nixos =
        { lib, ... }:
        lib.mkMerge [
          (lib.mkIf (host.hasAspect den.aspects.example-zfs-root) {
            # zfs-flavored impermanence wiring would go here
            # (e.g. rollback service on a zfs snapshot of the root dataset).
            environment.etc."example-impermanence-flavor".text = "zfs";
          })
          (lib.mkIf (host.hasAspect den.aspects.example-btrfs-root) {
            # btrfs-flavored impermanence wiring would go here
            # (e.g. snapshot rollback via btrfs subvolumes).
            environment.etc."example-impermanence-flavor".text = "btrfs";
          })
        ];
    };

  # ──────────────────────────────────────────────────────────────────
  # Pattern 2 — Deciding structure via `meta.handleWith` constraints
  # ──────────────────────────────────────────────────────────────────
  #
  # When the decision is STRUCTURAL ("which of these aspects should
  # actually be part of the tree?") rather than CONFIGURATIONAL ("given
  # this aspect is in the tree, how should it configure NixOS?"), the
  # right tool is `meta.handleWith` with an fx constraint such as
  # `den.lib.aspects.fx.constraints.exclude`.
  #
  # The constraint runs during the resolve tree walk and has full
  # structural visibility — and crucially, it operates ON the tree
  # rather than reading FROM INSIDE it, so it can't cycle.

  den.aspects.example-agenix-rekey.nixos = {
    environment.etc."example-secrets-provider".text = "agenix-rekey";
  };

  den.aspects.example-sops-nix.nixos = {
    environment.etc."example-secrets-provider".text = "sops-nix";
  };

  # To exclude one provider in favor of another, use:
  #   meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.example-sops-nix;
  den.aspects.example-secrets-bundle = {
    includes = [
      den.aspects.example-agenix-rekey
      den.aspects.example-sops-nix
    ];
    meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.example-sops-nix;
  };

  # ──────────────────────────────────────────────────────────────────
  # Anti-pattern — DO NOT use `hasAspect` to decide an `includes` list
  # ──────────────────────────────────────────────────────────────────
  #
  # The following shape looks plausible but produces an infinite
  # recursion at evaluation time:
  #
  #     den.aspects.broken =
  #       { host, ... }:
  #       {
  #         includes =
  #           if host.hasAspect den.aspects.example-zfs-root
  #           then [ den.aspects.example-zfs-impermanence ]
  #           else [ den.aspects.example-btrfs-impermanence ];
  #       };
  #
  # Why it cycles:
  #
  #   - `host.hasAspect` queries the resolved aspect tree.
  #   - The resolved aspect tree depends on every aspect's `includes`.
  #   - `broken`'s `includes` depends on `host.hasAspect`.
  #
  # That is a back-edge into the tree from a position the tree itself
  # has to read first to know its own shape — a classic fixed-point
  # with no fixed point. Nix evaluation reports infinite recursion.
  #
  # The correct tool for "decide what to include based on what else
  # is structurally present" is `meta.handleWith` with an fx constraint.
  # See `nix/lib/aspects/fx/constraints.nix` for available constraints:
  #
  #   - `exclude <ref>`              tombstone a specific aspect by reference
  #   - `substitute <ref> <aspect>`  swap one aspect for another
  #   - `filterBy <pred>`            custom predicate filtering
  #
  # These run during the tree walk with full structural visibility and
  # operate ON the tree rather than FROM INSIDE it, so they can't
  # cycle. Reach for them whenever the decision you want to make is
  # "which aspects should be in the tree?" rather than "given this
  # aspect is in the tree, what should it configure?"
}
