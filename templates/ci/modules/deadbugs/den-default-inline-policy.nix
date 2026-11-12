# Regression: a policy record built inside a `{ host, user }` include in
# den.default delivered twice. The include is also fanned out at the host
# scope for each user, and the copy's record is a new value, so it did not
# claim as the same registration. Worked on v0.19.0.
# Reported in GitHub #764.
{ denTest, lib, ... }:
let
  # A policy record built per evaluation of the include, so every copy of it
  # holds a new `fn` closure.
  inlinePolicy =
    den: name: module:
    (
      { host, user }:
      {
        name = "${name}/${user.userName}";
        includes = [
          {
            __isPolicy = true;
            inherit name;
            fn =
              { host, user, ... }:
              [
                (den.lib.policy.provide {
                  class = host.class;
                  module = module user;
                  receiver = host;
                })
              ];
          }
        ];
      }
    );
  shell =
    user:
    { pkgs, ... }:
    {
      users.users.${user.userName}.shell = pkgs.zsh;
    };
  group = g: user: { users.users.${user.userName}.extraGroups = [ g ]; };
  count = x: l: builtins.length (builtins.filter (y: y == x) l);

  cells = ack: {
    test-unique-option-once = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den.batteries.define-user
          (inlinePolicy den "my-shell" shell)
        ];
        expr = igloo.users.users.tux.shell.pname;
        expected = "zsh";
      }
    );
    # A list option takes a second delivery silently; count it.
    test-list-option-once = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den.batteries.define-user
          (inlinePolicy den "my-group" (group "probe"))
        ];
        expr = count "probe" igloo.users.users.tux.extraGroups;
        expected = 1;
      }
    );
    test-two-users-once-each = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.default.includes = [
          den.batteries.define-user
          (inlinePolicy den "my-group" (group "probe"))
        ];
        expr = map (u: count "probe" igloo.users.users.${u}.extraGroups) [
          "tux"
          "pingu"
        ];
        expected = [
          1
          1
        ];
      }
    );
    # Two different records under one name are two registrations: both land.
    test-namesakes-both-land = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den.batteries.define-user
          (inlinePolicy den "same" (group "first"))
          (inlinePolicy den "same" (group "second"))
        ];
        expr = map (g: count g igloo.users.users.tux.extraGroups) [
          "first"
          "second"
        ];
        expected = [
          1
          1
        ];
      }
    );
    # Control: the same include on the user aspect.
    test-on-user-once = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den.batteries.define-user ];
        den.aspects.tux.includes = [ (inlinePolicy den "my-group" (group "probe")) ];
        expr = count "probe" igloo.users.users.tux.extraGroups;
        expected = 1;
      }
    );
    test-user-shell-battery = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den.batteries.define-user
          (den.batteries.user-shell "fish")
        ];
        expr = igloo.users.users.tux.shell.pname;
        expected = "fish";
      }
    );
    # A record whose `fn` reads `user` from the include, not from its own
    # arguments: each user's copy is its own registration.
    test-captured-user-once-each = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.default.includes = [
          den.batteries.define-user
          (
            { host, user }:
            {
              name = "captured/${user.userName}";
              includes = [
                {
                  __isPolicy = true;
                  name = "captured";
                  fn =
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = host.class;
                        module.users.users.${user.userName}.extraGroups = [ "captured-${user.userName}" ];
                        receiver = host;
                      })
                    ];
                }
              ];
            }
          )
        ];
        expr = map (u: count "captured-${u}" igloo.users.users.${u}.extraGroups) [
          "tux"
          "pingu"
        ];
        expected = [
          1
          1
        ];
      }
    );
    # Two different records under one name in one include: both land.
    test-namesakes-in-one-include = denTest (
      { den, igloo, ... }:
      let
        record = g: {
          __isPolicy = true;
          name = "same";
          fn =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = host.class;
                module = group g user;
                receiver = host;
              })
            ];
        };
      in
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den.batteries.define-user
          (
            { host, user }:
            {
              name = "pair/${user.userName}";
              includes = [
                (record "first")
                (record "second")
              ];
            }
          )
        ];
        expr = map (g: count g igloo.users.users.tux.extraGroups) [
          "first"
          "second"
        ];
        expected = [
          1
          1
        ];
      }
    );
    # The record sits in a static aspect inside the include.
    test-nested-once = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den.batteries.define-user
          (
            { host, user }:
            {
              name = "outer/${user.userName}";
              includes = [
                {
                  name = "inner/${user.userName}";
                  includes = [ ((inlinePolicy den "nested" (group "nested")) { inherit host user; }) ];
                }
              ];
            }
          )
        ];
        expr = count "nested" igloo.users.users.tux.extraGroups;
        expected = 1;
      }
    );
    # A bare include from the policy reaches the host once per user.
    test-bare-include-once-each = denTest (
      { den, igloo, ... }:
      {
        den.migrations.user-host-content.acknowledged = ack;
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.default.includes = [
          den.batteries.define-user
          (
            { host, user }:
            {
              name = "bare/${user.userName}";
              includes = [
                {
                  __isPolicy = true;
                  name = "bare";
                  fn =
                    { host, user, ... }:
                    [ (den.lib.policy.include { nixos.users.users.${user.userName}.extraGroups = [ "bare" ]; }) ];
                }
              ];
            }
          )
        ];
        expr = map (u: count "bare" igloo.users.users.${u}.extraGroups) [
          "tux"
          "pingu"
        ];
        expected = [
          1
          1
        ];
      }
    );
  };
in
{
  flake.tests.den-default-inline-policy = {
    transition = cells false;
    acknowledged = cells true;
  };
}
