{ denTest, ... }:
{
  flake.tests.issue-540-conditional-first-include = {
    # Guard on an aspect included by a later sibling. The conditional is walked
    # first, so the guard fails initially. Drain must wait until all siblings
    # are resolved before re-evaluating.
    test-conditional-before-dependency = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.conditional
          den.aspects.base
        ];

        den.aspects.base.includes = [
          den.aspects.git
        ];

        den.aspects.conditional = {
          includes = [
            (den.lib.policy.when ({ host, ... }: host.hasAspect den.aspects.git) {
              nixos.environment.variables.GIT_ENABLED = "true";
            })
          ];
        };

        den.aspects.git.nixos.programs.git.enable = true;

        expr = igloo.environment.variables ? GIT_ENABLED;
        expected = true;
      }
    );

    # Same but via schema includes at the same level.
    test-conditional-same-level-schema = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.host.includes = [
          den.aspects.conditional
          den.aspects.base
        ];

        den.aspects.base.includes = [
          den.aspects.git
        ];

        den.aspects.conditional = {
          includes = [
            (den.lib.policy.when ({ host, ... }: host.hasAspect den.aspects.git) {
              nixos.environment.variables.GIT_ENABLED = "true";
            })
          ];
        };

        den.aspects.git.nixos.programs.git.enable = true;

        expr = igloo.environment.variables ? GIT_ENABLED;
        expected = true;
      }
    );

    # Multiple guards with different dependencies resolve in the same drain.
    # Tests that the fixed-point drain handles interleaved pass/fail correctly.
    test-chained-guards = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.base
        ];

        den.aspects.base.nixos.programs.git.enable = true;

        # Guard B fires first (git is present), emits editor aspect.
        den.schema.host.includes = [
          (policy.when ({ host, ... }: host.hasAspect den.aspects.editor) {
            nixos.environment.variables.EDITOR_CONFIGURED = "true";
          })
          (policy.when ({ host, ... }: host.hasAspect den.aspects.base) {
            nixos.networking.hostName = "has-base";
          })
          den.aspects.editor
        ];

        den.aspects.editor.nixos.environment.variables.EDITOR = "vim";

        expr = {
          hasBase = igloo.networking.hostName;
          editorConfigured = igloo.environment.variables ? EDITOR_CONFIGURED;
        };
        expected = {
          hasBase = "has-base";
          editorConfigured = true;
        };
      }
    );

    # True multi-pass convergence: Guard A depends on aspect X which only
    # enters the pathSet because Guard B passed and emitted it.
    # Pass 1: B passes (base in pathSet), emits tooling (which includes editor).
    #         A fails (editor not yet in pathSet — emitIncludes runs after eval).
    # Pass 2: A passes (editor now in pathSet from B's emission).
    test-multi-pass-convergence = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [
          den.aspects.base
        ];

        den.aspects.base.nixos.programs.git.enable = true;

        # Guard A: depends on editor (not in pathSet until B emits tooling).
        # Guard B: depends on base (in pathSet), emits tooling which includes editor.
        den.schema.host.includes = [
          (policy.when ({ host, ... }: host.hasAspect den.aspects.editor) {
            nixos.environment.variables.EDITOR_CONFIGURED = "true";
          })
          (policy.when ({ host, ... }: host.hasAspect den.aspects.base) (policy.include den.aspects.tooling))
        ];

        den.aspects.tooling.includes = [ den.aspects.editor ];
        den.aspects.editor.nixos.environment.variables.EDITOR = "vim";

        expr = {
          hasEditor = igloo.environment.variables ? EDITOR;
          editorConfigured = igloo.environment.variables ? EDITOR_CONFIGURED;
        };
        expected = {
          hasEditor = true;
          editorConfigured = true;
        };
      }
    );
  };
}
