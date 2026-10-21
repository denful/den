# Two related bugs in simple `policy.route`, surfaced by a guarded route that
# uses `intoPath` (the forward-style target-path name).
#
# Bug 1 (route/wrap.nix `guardModule`): a guarded route whose guard is false
# crashed with
#   error: The option `_file' does not exist. Definition values:
#     { _type = "if"; condition = false; content = "foo@igloo"; }
# because the raw collector module `{ key; _file; imports }` was merged under
# `config` (metadata mis-read as options) and gated with `mkIf` (which still
# requires the target option to exist). Fixed by gating with `optionalAttrs`
# (matching the forward path) and recursing into structural imports.
#
# Bug 2 (policy-effects.nix `route`): `intoPath` was silently dropped — only
# `path` was read — so content landed at the class root instead of nesting.
# Fixed by accepting `intoPath` as the public alias for `path`.
{ denTest, lib, ... }:
let
  mkBox =
    name:
    { lib, ... }:
    {
      options.${name} = lib.mkOption {
        type = lib.types.submoduleWith {
          modules = [
            {
              options.items = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            }
          ];
        };
        default = { };
      };
    };
in
{
  flake.tests.deadbugs.route-intopath-conditional-leak = {

    # Bug 1: guard false (nixos has no `foo` option) → route contributes
    # nothing, cleanly, instead of crashing.
    test-guarded-route-skips-cleanly = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.classes.foo.description = "foo class";

        den.policies.foo-to-host =
          { host, ... }:
          den.lib.policy.route {
            fromClass = "foo";
            intoClass = host.class;
            intoPath = [ "foo" ];
            guard = { options, ... }: options ? foo;
          };

        den.schema.host.includes = [ den.policies.foo-to-host ];

        den.aspects.igloo.foo.bar = "baz";

        expr = igloo ? foo;
        expected = false;
      }
    );

    # Bug 2: `intoPath` nests content at the target path (was silently dropped,
    # landing at the class root).
    test-intopath-nests = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.src.description = "src class";

        den.policies.src-to-host =
          { host, ... }:
          den.lib.policy.route {
            fromClass = "src";
            intoClass = host.class;
            intoPath = [ "wrapper" ];
          };

        den.default.includes = [ den.policies.src-to-host ];

        den.aspects.igloo = {
          nixos.imports = [ (mkBox "wrapper") ];
          src.items = [ "routed" ];
        };

        expr = igloo.wrapper.items;
        expected = [ "routed" ];
      }
    );

  };
}
