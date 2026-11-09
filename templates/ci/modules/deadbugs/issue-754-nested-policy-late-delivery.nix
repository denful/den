# Reported in GitHub #754: a policy nested in an aspect that reaches its
# firing scope through a late delivery (a host's provides.to-users or
# provides.<user>, a user's provides.to-hosts, a host or user policy's
# include) registers there after that scope's own dispatch, and late dispatch's
# entity-kind filter dropped it when its fn names no argument of the
# scope's kind (`{ host, ... }:` at a user). The grid crosses delivery path,
# nesting and the nested policy's shape; each cell expects the delivered
# value, which is main's wherever main expressed the cell.
{ denTest, lib, ... }:
{
  flake.tests.deadbugs.issue-754-nested-policy-late-delivery = {
    # main dropped this; fixed in #754.
    "test-to-users--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-users--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-users--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-users--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-users--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-users--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-users--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-users--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-users--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-users--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-users--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-users--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-to-users--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({ includes = [ (den.batteries.unfree [ "g" ]) ]; })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-to-users--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [ (den.batteries.unfree [ "g" ]) ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-to-users--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-to-users--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.g.text = "x";
                  })
                ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-to-users--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "nixos";
                        receiver = host;
                        module.environment.etc.g.text = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-to-users--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-users--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "homeManager";
                    receiver = user;
                    module.home.sessionVariables.G = "x";
                  })
                ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-users--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "homeManager";
                        receiver = user;
                        module.home.sessionVariables.G = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-users--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.to-users.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-named-user--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-named-user--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-named-user--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-named-user--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-named-user--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-named-user--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-named-user--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-named-user--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-named-user--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-named-user--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-named-user--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-named-user--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-named-user--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [ ({ includes = [ (den.batteries.unfree [ "g" ]) ]; }) ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-named-user--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [ (den.batteries.unfree [ "g" ]) ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-named-user--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-named-user--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.g.text = "x";
                  })
                ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-named-user--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "nixos";
                        receiver = host;
                        module.environment.etc.g.text = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-named-user--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-named-user--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "homeManager";
                    receiver = user;
                    module.home.sessionVariables.G = "x";
                  })
                ]
              ))
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-named-user--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "homeManager";
                        receiver = user;
                        module.home.sessionVariables.G = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-named-user--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.dev.provides.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.aspects.igloo.includes = [ den.aspects.dev ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-hosts--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-hosts--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-hosts--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-hosts--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-hosts--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-hosts--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-hosts--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-hosts--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-hosts--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-hosts--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-hosts--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-to-hosts--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-to-hosts--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({ includes = [ (den.batteries.unfree [ "g" ]) ]; })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-to-hosts--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [ (den.batteries.unfree [ "g" ]) ];
              }
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-to-hosts--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              )
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-to-hosts--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.g.text = "x";
                  })
                ]
              ))
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-to-hosts--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "nixos";
                        receiver = host;
                        module.environment.etc.g.text = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-to-hosts--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-to-hosts--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "homeManager";
                    receiver = user;
                    module.home.sessionVariables.G = "x";
                  })
                ]
              ))
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-hosts--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "homeManager";
                        receiver = user;
                        module.home.sessionVariables.G = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-to-hosts--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.provides.to-hosts.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-host-policy--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-host-policy--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-host-policy--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-policy--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-policy--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-policy--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-policy--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-policy--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-policy--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-host-policy--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-host-policy--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-host-policy--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-host-policy--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [ (den.lib.policy.include ({ includes = [ (den.batteries.unfree [ "g" ]) ]; })) ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-host-policy--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-host-policy--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [ (den.batteries.unfree [ "g" ]) ];
                  }
                )
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-host-policy--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "nixos";
                      receiver = host;
                      module.environment.etc.g.text = "x";
                    })
                  ]
                ))
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-host-policy--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-host-policy--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }:
                        [
                          (den.lib.policy.provide {
                            class = "nixos";
                            receiver = host;
                            module.environment.etc.g.text = "x";
                          })
                        ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-policy--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, user, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "homeManager";
                      receiver = user;
                      module.home.sessionVariables.G = "x";
                    })
                  ]
                ))
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-policy--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-policy--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.hp =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, user, ... }:
                        [
                          (den.lib.policy.provide {
                            class = "homeManager";
                            receiver = user;
                            module.home.sessionVariables.G = "x";
                          })
                        ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.igloo.includes = [ den.policies.hp ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [ ({ includes = [ (den.batteries.unfree [ "g" ]) ]; }) ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-user-direct--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [ (den.batteries.unfree [ "g" ]) ];
              }
            ];
          })
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-user-direct--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              )
            ];
          })
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-user-direct--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.g.text = "x";
                  })
                ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "nixos";
                        receiver = host;
                        module.environment.etc.g.text = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-direct--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "homeManager";
                    receiver = user;
                    module.home.sessionVariables.G = "x";
                  })
                ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "homeManager";
                        receiver = user;
                        module.home.sessionVariables.G = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-direct--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-direct--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-direct--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-direct--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # A host-scope include of homeManager content stays at the host, on main too.
    "test-host-direct--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = false;
      }
    );
    # A host-scope include of homeManager content stays at the host, on main too.
    "test-host-direct--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = false;
      }
    );
    # A host-scope include of homeManager content stays at the host, on main too.
    "test-host-direct--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = false;
      }
    );
    "test-host-direct--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [ ({ includes = [ (den.batteries.unfree [ "g" ]) ]; }) ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-host-direct--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [ (den.batteries.unfree [ "g" ]) ];
              }
            ];
          })
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-host-direct--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              )
            ];
          })
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-host-direct--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.g.text = "x";
                  })
                ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "nixos";
                        receiver = host;
                        module.environment.etc.g.text = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-host-direct--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "homeManager";
                    receiver = user;
                    module.home.sessionVariables.G = "x";
                  })
                ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-direct--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "homeManager";
                        receiver = user;
                        module.home.sessionVariables.G = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-host-direct--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.igloo.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [ ({ includes = [ (den.batteries.unfree [ "g" ]) ]; }) ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-schema-user--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [ (den.batteries.unfree [ "g" ]) ];
              }
            ];
          })
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-schema-user--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              )
            ];
          })
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    "test-schema-user--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, ... }:
                [
                  (den.lib.policy.provide {
                    class = "nixos";
                    receiver = host;
                    module.environment.etc.g.text = "x";
                  })
                ]
              ))
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "nixos";
                        receiver = host;
                        module.environment.etc.g.text = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-schema-user--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (den.lib.policy.mkPolicy "g" (
                { host, user, ... }:
                [
                  (den.lib.policy.provide {
                    class = "homeManager";
                    receiver = user;
                    module.home.sessionVariables.G = "x";
                  })
                ]
              ))
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              {
                name = "inner";
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "homeManager";
                        receiver = user;
                        module.home.sessionVariables.G = "x";
                      })
                    ]
                  ))
                ];
              }
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-schema-user--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          ({
            includes = [
              (
                { host, ... }:
                {
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              )
            ];
          })
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-schema-policy--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-schema-policy--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  {
                    name = "inner";
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                      ))
                    ];
                  }
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-schema-policy--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (
                    { host, ... }:
                    {
                      includes = [
                        (den.lib.policy.mkPolicy "g" (
                          { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                        ))
                      ];
                    }
                  )
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                  ))
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  {
                    name = "inner";
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                      ))
                    ];
                  }
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (
                    { host, ... }:
                    {
                      includes = [
                        (den.lib.policy.mkPolicy "g" (
                          { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                        ))
                      ];
                    }
                  )
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  {
                    name = "inner";
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                      ))
                    ];
                  }
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (
                    { host, ... }:
                    {
                      includes = [
                        (den.lib.policy.mkPolicy "g" (
                          { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                        ))
                      ];
                    }
                  )
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-schema-policy--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                  ))
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-schema-policy--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  {
                    name = "inner";
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                      ))
                    ];
                  }
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-schema-policy--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (
                    { host, ... }:
                    {
                      includes = [
                        (den.lib.policy.mkPolicy "g" (
                          { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                        ))
                      ];
                    }
                  )
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-user-schema-policy--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [ (den.lib.policy.include ({ includes = [ (den.batteries.unfree [ "g" ]) ]; })) ]
          ))
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-user-schema-policy--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  {
                    name = "inner";
                    includes = [ (den.batteries.unfree [ "g" ]) ];
                  }
                ];
              }))
            ]
          ))
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-user-schema-policy--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (
                    { host, ... }:
                    {
                      includes = [ (den.batteries.unfree [ "g" ]) ];
                    }
                  )
                ];
              }))
            ]
          ))
        ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-user-schema-policy--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "nixos";
                        receiver = host;
                        module.environment.etc.g.text = "x";
                      })
                    ]
                  ))
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-user-schema-policy--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  {
                    name = "inner";
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }:
                        [
                          (den.lib.policy.provide {
                            class = "nixos";
                            receiver = host;
                            module.environment.etc.g.text = "x";
                          })
                        ]
                      ))
                    ];
                  }
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-user-schema-policy--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (
                    { host, ... }:
                    {
                      includes = [
                        (den.lib.policy.mkPolicy "g" (
                          { host, ... }:
                          [
                            (den.lib.policy.provide {
                              class = "nixos";
                              receiver = host;
                              module.environment.etc.g.text = "x";
                            })
                          ]
                        ))
                      ];
                    }
                  )
                ];
              }))
            ]
          ))
        ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (den.lib.policy.mkPolicy "g" (
                    { host, user, ... }:
                    [
                      (den.lib.policy.provide {
                        class = "homeManager";
                        receiver = user;
                        module.home.sessionVariables.G = "x";
                      })
                    ]
                  ))
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  {
                    name = "inner";
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, user, ... }:
                        [
                          (den.lib.policy.provide {
                            class = "homeManager";
                            receiver = user;
                            module.home.sessionVariables.G = "x";
                          })
                        ]
                      ))
                    ];
                  }
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-schema-policy--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.schema.user.includes = [
          (den.lib.policy.mkPolicy "up" (
            { host, user, ... }:
            [
              (den.lib.policy.include ({
                includes = [
                  (
                    { host, ... }:
                    {
                      includes = [
                        (den.lib.policy.mkPolicy "g" (
                          { host, user, ... }:
                          [
                            (den.lib.policy.provide {
                              class = "homeManager";
                              receiver = user;
                              module.home.sessionVariables.G = "x";
                            })
                          ]
                        ))
                      ];
                    }
                  )
                ];
              }))
            ]
          ))
        ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-aspect-policy--pol-host-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-aspect-policy--pol-host-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-aspect-policy--pol-host-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-hostuser-incl-nixos--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-hostuser-incl-nixos--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-hostuser-incl-nixos--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.g.text = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-user-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-user-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-user-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-aspect-policy--pol-host-incl-hm--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                ))
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-aspect-policy--pol-host-incl-hm--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # main dropped this; fixed in #754.
    "test-user-aspect-policy--pol-host-incl-hm--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.G = "x"; }) ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-user-aspect-policy--battery-unfree--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [ (den.lib.policy.include ({ includes = [ (den.batteries.unfree [ "g" ]) ]; })) ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-user-aspect-policy--battery-unfree--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [ (den.batteries.unfree [ "g" ]) ];
                }
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # #753 moved this onto a nested policy; fixed in #754.
    "test-user-aspect-policy--battery-unfree--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [ (den.batteries.unfree [ "g" ]) ];
                  }
                )
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = builtins.elem "g" igloo.unfree.packages;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-user-aspect-policy--pol-host-provide-host--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "nixos";
                      receiver = host;
                      module.environment.etc.g.text = "x";
                    })
                  ]
                ))
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-user-aspect-policy--pol-host-provide-host--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "nixos";
                          receiver = host;
                          module.environment.etc.g.text = "x";
                        })
                      ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    # A receiver delivery (#746, not on main), dropped the same way; fixed in #754.
    "test-user-aspect-policy--pol-host-provide-host--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, ... }:
                        [
                          (den.lib.policy.provide {
                            class = "nixos";
                            receiver = host;
                            module.environment.etc.g.text = "x";
                          })
                        ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.environment.etc ? g;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-hostuser-provide-user--n0" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (den.lib.policy.mkPolicy "g" (
                  { host, user, ... }:
                  [
                    (den.lib.policy.provide {
                      class = "homeManager";
                      receiver = user;
                      module.home.sessionVariables.G = "x";
                    })
                  ]
                ))
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-hostuser-provide-user--n1" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                {
                  name = "inner";
                  includes = [
                    (den.lib.policy.mkPolicy "g" (
                      { host, user, ... }:
                      [
                        (den.lib.policy.provide {
                          class = "homeManager";
                          receiver = user;
                          module.home.sessionVariables.G = "x";
                        })
                      ]
                    ))
                  ];
                }
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
    "test-user-aspect-policy--pol-hostuser-provide-user--n2" = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.up =
          { host, user, ... }:
          [
            (den.lib.policy.include ({
              includes = [
                (
                  { host, ... }:
                  {
                    includes = [
                      (den.lib.policy.mkPolicy "g" (
                        { host, user, ... }:
                        [
                          (den.lib.policy.provide {
                            class = "homeManager";
                            receiver = user;
                            module.home.sessionVariables.G = "x";
                          })
                        ]
                      ))
                    ];
                  }
                )
              ];
            }))
          ];
        den.aspects.tux.includes = [ den.policies.up ];
        expr = igloo.home-manager.users.tux.home.sessionVariables ? G;
        expected = true;
      }
    );
  };
}
