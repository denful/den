{
  den,
  lib,
  inputs,
  ...
}:
let
  host-has-user-with-class =
    host: class: builtins.any (user: lib.elem class user.classes) (lib.attrValues host.users);

  mkDetectHost =
    {
      className,
      supportedOses ? [
        "nixos"
        "darwin"
      ],
      optionPath,
    }:
    { host, ... }:
    let
      isOsSupported = builtins.elem host.class supportedOses;
      isEnabled = (host.${optionPath} or { }).enable or false;
      hostHasClass = host-has-user-with-class host className;
    in
    isEnabled && isOsSupported && hostHasClass;

  mkIntoClassUsers =
    className:
    { host, ... }:
    map (user: { inherit host user; }) (
      lib.filter (u: lib.elem className u.classes) (lib.attrValues host.users)
    );

  hostOptions =
    {
      className,
      optionPath,
      getModule,
    }:
    { host, ... }:
    {
      options.${optionPath} = {
        enable = lib.mkOption {
          type = lib.types.bool;
          defaultText = lib.literalExpression "host-has-user-with-class host className";
          default = host-has-user-with-class host className;
        };
        module = lib.mkOption {
          type = lib.types.deferredModule;
          defaultText = lib.literalExpression "getModule { inherit host inputs; }";
          default = getModule { inherit host inputs; };
        };
      };
    };

  # Self-contained battery: host → user routing via aspect-included policy.
  # The battery is an aspect with policies — include it in den.schema.host.includes
  # and its policy fires during host resolution without separate den.policies registration.
  makeHomeEnv =
    {
      className,
      ctxName ? className,
      supportedOses ? [
        "nixos"
        "darwin"
      ],
      optionPath,
      getModule,
      forwardPathFn,
      schemaIncludes ? [ ],
    }:
    let
      # Keyed module wrapper: the NixOS module system deduplicates imports
      # with the same `key`, so this fires once even when included from
      # multiple user entity resolves.
      hostModuleKeyed = host: {
        key = "den:${optionPath}-host-module";
        imports = [ host.${optionPath}.module ];
      };
      hostModule =
        { host }:
        {
          ${host.class}.imports = [ (hostModuleKeyed host) ];
        };

      userForward =
        { host, user }:
        den.batteries.forward {
          each = lib.singleton true;
          fromClass = _: className;
          intoClass = _: host.class;
          intoPath = _: forwardPathFn { inherit host user; };
          # The forward source resolves via spawnNode (threaded with the
          # parent scope-tree state), so parametric host aspects re-fired at the
          # user scope bind the same ancestor args (e.g. `environment`) they
          # would at the host scope — no manual chainCtx threading needed.
          fromAspect = _: den.lib.resolveEntity "user" { inherit host user; };
          receiver = host;
        };

      # Host-scope arm: the host's own content. The module import is a provide
      # at the host scope: an include of `hostModule` here is shared with the
      # user-scope arm's include, so it lands nothing at the host, and
      # excluding the user arm would leave the host without the module (#694).
      # The key deduplicates it against the user arm's delivery.
      classIncludes =
        host:
        [
          (den.lib.policy.provide {
            class = host.class;
            module = hostModuleKeyed host;
          })
        ]
        ++ lib.optional (den.aspects ? os-user-class-fwd) (
          den.lib.policy.include den.aspects.os-user-class-fwd
        );

      # User-scope arm: the same content, delivered to the host. The key
      # deduplicates it against the host-scope arm.
      userClassDeliveries =
        { host, ... }:
        [
          (den.lib.policy.provide {
            class = host.class;
            module = hostModuleKeyed host;
            receiver = host;
          })
        ]
        ++ lib.optional (den.aspects ? os-user-class-fwd) (
          den.lib.policy.include den.aspects.os-user-class-fwd
        );

      # The hook's host-class output, resolved at the user's ctx, crosses to the
      # host; its other classes stay local through the include above. Its own
      # schema policy: provides dedup by policy name, class and path, so sharing
      # userDetectFn with the host-module provide would drop one of them.
      hookDeliveryFn =
        {
          host,
          user,
          home ? null,
          ...
        }@userCtx:
        lib.optional
          (
            den.aspects ? os-user-class-fwd
            && builtins.elem host.class supportedOses
            && lib.elem className user.classes
            && home == null
            # An accepted user's bucket reaches the host whole, the include's
            # copy with it.
            && !(den.lib.acceptance.acceptsExplicitly userCtx host user)
          )
          (
            den.lib.policy.provide {
              class = host.class;
              module =
                _:
                den.lib.aspects.resolve host.class (den.lib.acceptance.atCtx userCtx den.aspects.os-user-class-fwd);
              receiver = host;
              # Accepted only through user-aspects' transition default: the
              # bucket carries it, so this stands down, recorded for the
              # migration warning (#694).
              __standDown = den.lib.acceptance.accepts userCtx host user;
              __standDownAspect = "os-user-class-fwd";
            }
          );

      # The env's schema includes apply to the host (included at the host scope
      # below) and to its users (for their user-env classes). At the user scope
      # their host-class content would stay in the user, so it is stripped
      # there; the host copy carries it (#694).
      stripHostClass =
        host: inc:
        let
          drop = [
            host.class
            "os"
          ];
          stripAttrs =
            a:
            builtins.removeAttrs a drop
            // lib.optionalAttrs (a ? includes) { includes = map (stripHostClass host) a.includes; };
        in
        if builtins.isAttrs inc && !(inc ? __functor) then
          stripAttrs inc
        else if lib.isFunction inc then
          lib.setFunctionArgs (args: stripHostClass host (inc args)) (lib.functionArgs inc)
        else
          inc;

      policyFn =
        { host, ... }:
        let
          enabled = mkDetectHost {
            inherit className supportedOses optionPath;
          } { inherit host; };
        in
        if !enabled then
          [ ]
        else
          let
            pairs = mkIntoClassUsers className { inherit host; };
            resolves = map (
              pair:
              den.lib.policy.resolve.withIncludes ([ userForward ] ++ map (stripHostClass host) schemaIncludes) {
                user = pair.user;
              }
            ) pairs;
          in
          resolves ++ classIncludes host;

      # The env's schema includes at the host scope, as their own policy:
      # includes a policy returns beside its resolves are handed to the
      # resolved users too, which would put the host-class content back in
      # the users (#694).
      hostSchemaFn =
        { host, ... }:
        lib.optionals (mkDetectHost { inherit className supportedOses optionPath; } { inherit host; }) (
          map (inc: den.lib.policy.include inc) schemaIncludes
        );

      # Complements the host-scope battery which only sees users
      # declared on host.users, not registry or policy-resolved users.
      userDetectFn =
        {
          host,
          user,
          home ? null,
          ...
        }:
        let
          isOsSupported = builtins.elem host.class supportedOses;
          hasClass = lib.elem className user.classes;
        in
        # A standalone home binds a host that is not its ancestor: no receiver.
        lib.optionals (isOsSupported && hasClass && home == null) (
          [
            (den.lib.policy.include (userForward {
              inherit host user;
            }))
          ]
          ++ userClassDeliveries { inherit host user; }
        );
    in
    {
      battery = {
        policies."host-to-${ctxName}-users" = policyFn;
        includes = [
          {
            __isPolicy = true;
            name = "host-to-${ctxName}-users";
            fn = policyFn;
          }
          {
            __isPolicy = true;
            name = "host-to-${ctxName}-schema-includes";
            fn = hostSchemaFn;
          }
        ];
      };

      # User-scope policy for user schema includes.
      userDetect = {
        policies."${ctxName}-user-detect" = userDetectFn;
        includes = [
          {
            __isPolicy = true;
            name = "${ctxName}-user-detect";
            fn = userDetectFn;
          }
          {
            __isPolicy = true;
            name = "${ctxName}-os-user-class-fwd-host";
            fn = hookDeliveryFn;
          }
        ];
      };

      hostConf = hostOptions {
        inherit
          className
          optionPath
          getModule
          ;
      };

    };

in
{
  inherit makeHomeEnv mkDetectHost mkIntoClassUsers;
}
