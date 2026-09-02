# Effect handler: compile-static
# Gates, classifies, emits classes, resolves nested keys, resolves children.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects) isMeaningfulName;
  inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;
  inherit (import ./gate-tag.nix { inherit fx; }) gateAndTag;

  inherit (import ../aspect { inherit lib den; } { inherit ctxFromHandlers; })
    registerConstraints
    ;

  parametricInternalKeys = [
    "__fn"
    "__args"
    "__parametricDepth"
    "__parametricResolvedArgs"
  ];

in
{
  compileStaticHandler = {
    "compile-static" =
      { param, state }:
      let
        raw = param.aspect;
        aspect = builtins.removeAttrs raw parametricInternalKeys;
        nodeIdentity = identity.key aspect;
        chainIdentity = identity.pathKey (identity.ownChain aspect ++ [ (aspect.name or "<anon>") ]);
        isMeaningful = isMeaningfulName (aspect.name or "<anon>");
      in
      {
        resume =
          # Step 1: gate check (dedup + constraint) — skipped on parametric re-entry
          gateAndTag { inherit param aspect; } (
            tagged:
            # Step 2: probe for class handler, classify, emit, nest, resolve-children
            fx.bind (fx.effects.hasHandler "class") (
              hasClassHandler:
              fx.bind (if hasClassHandler then fx.send "class" null else fx.pure null) (
                targetClass:
                fx.bind
                  (fx.send "classify" {
                    aspect = tagged;
                    inherit targetClass;
                  })
                  (
                    classified:
                    # Nested keys are classified but never auto-walked.
                    # Sub-aspects must be explicitly included to emit class
                    # modules — this matches provides behavior and keeps
                    # activation explicit.
                    fx.bind
                      (fx.seq ([
                        (fx.send "emit-classes" {
                          aspect = tagged;
                          classKeys = classified.classKeys;
                          pipeKeys = classified.pipeKeys or [ ];
                          identity = nodeIdentity;
                        })
                        (registerConstraints tagged)
                      ]))
                      (
                        _:
                        fx.bind (fx.send "resolve-children" {
                          aspect = tagged;
                          inherit isMeaningful chainIdentity;
                        }) (resolved: fx.pure [ resolved ])
                      )
                  )
              )
            )
          );
        inherit state;
      };
  };
}
