{
  denTest,
  inputs,
  ...
}:
{
  flake.tests.include-children = {

    # Basic: ._ includes all immediate child aspect keys
    test-include-children-basic = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.servers.web.nixos.networking.hostName = "web-host";
        den.aspects.servers.db.nixos.services.postgresql.enable = true;

        den.aspects.igloo.includes = [ den.aspects.servers._ ];

        expr = {
          hostName = igloo.networking.hostName;
          pg = igloo.services.postgresql.enable;
        };
        expected = {
          hostName = "web-host";
          pg = true;
        };
      }
    );

    # Empty: aspect with no freeform children — ._ is harmless
    test-include-children-empty = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.empty = { };
        den.aspects.igloo = {
          nixos.networking.hostName = "still-here";
          includes = [ den.aspects.empty._ ];
        };

        expr = igloo.networking.hostName;
        expected = "still-here";
      }
    );

    # Mixed: class keys on aspect are not included, only nested children
    test-include-children-skips-class-keys = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.mixed = {
          nixos.networking.hostName = "should-not-leak";
          child.nixos.services.openssh.enable = true;
        };

        den.aspects.igloo.includes = [ den.aspects.mixed._ ];

        # class key (nixos) must not leak — hostName stays at NixOS default
        expr = {
          ssh = igloo.services.openssh.enable;
          hostName = igloo.networking.hostName;
        };
        expected = {
          ssh = true;
          hostName = "nixos";
        };
      }
    );

    # Provides children remain accessible alongside synthetic aspect
    test-include-children-with-provides = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.infra = {
          provides.monitoring.nixos.services.prometheus.enable = true;
          networking.nixos.networking.firewall.enable = true;
        };

        den.aspects.igloo.includes = [
          den.aspects.infra._
          den.aspects.infra._.monitoring
        ];

        expr = {
          firewall = igloo.networking.firewall.enable;
          prom = igloo.services.prometheus.enable;
        };
        expected = {
          firewall = true;
          prom = true;
        };
      }
    );

    # ._ does not expose synthetic name/includes to attrNames
    test-include-children-attrvalues-compat = denTest (
      {
        den,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.parent = {
          provides.a.nixos = { };
          provides.b.nixos = { };
          child.nixos = { };
        };

        # name and includes must not appear — they would break
        # lib.attrValues patterns that expect only provides children.
        expr = {
          hasName = den.aspects.parent._ ? name;
          hasIncludes = den.aspects.parent._ ? includes;
        };
        expected = {
          hasName = false;
          hasIncludes = false;
        };
      }
    );

    # ._ only includes immediate children, not grandchildren
    test-include-children-no-grandchildren = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.top.mid.deep.nixos.services.openssh.enable = true;
        den.aspects.top.sibling.nixos.services.timesyncd.enable = true;

        den.aspects.igloo.includes = [ den.aspects.top._ ];

        # mid and sibling are included but deep (grandchild) is not —
        # mid must be explicitly included or have its own ._ for deep to resolve.
        expr = {
          time = igloo.services.timesyncd.enable;
          ssh = igloo.services.openssh.enable or false;
        };
        expected = {
          time = true;
          ssh = false;
        };
      }
    );

    # Parametric children resolve through ._
    test-include-children-parametric = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.services.sshd =
          { host, ... }:
          {
            nixos.services.openssh.enable = true;
          };
        den.aspects.services.ntp.nixos.services.timesyncd.enable = true;

        den.aspects.igloo.includes = [ den.aspects.services._ ];

        expr = {
          ssh = igloo.services.openssh.enable;
          time = igloo.services.timesyncd.enable;
        };
        expected = {
          ssh = true;
          time = true;
        };
      }
    );
    # ._ works on nested (wrapped) aspects, not just root aspects
    test-include-children-nested = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.top.mid.deep.nixos.services.openssh.enable = true;
        den.aspects.top.mid.shallow.nixos.services.timesyncd.enable = true;

        # mid._ should collect deep and shallow
        den.aspects.igloo.includes = [ den.aspects.top.mid._ ];

        expr = {
          ssh = igloo.services.openssh.enable;
          time = igloo.services.timesyncd.enable;
        };
        expected = {
          ssh = true;
          time = true;
        };
      }
    );

    # Chained ._ at multiple nesting levels
    test-include-children-nested-chained = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.infra.net.fw.nixos.networking.firewall.enable = true;
        den.aspects.infra.net.dns.nixos.networking.nameservers = [ "1.1.1.1" ];

        # top-level ._ includes net; net._ includes fw and dns
        den.aspects.igloo.includes = [ den.aspects.infra.net._ ];

        expr = {
          fw = igloo.networking.firewall.enable;
          dns = igloo.networking.nameservers;
        };
        expected = {
          fw = true;
          dns = [ "1.1.1.1" ];
        };
      }
    );

    # Nested ._ with mixed content: class keys + child aspects on same wrapper
    test-include-children-nested-mixed = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # sub has both a class key (nixos) and child aspects (a, b)
        den.aspects.group.sub.nixos.networking.hostName = "from-sub";
        den.aspects.group.sub.a.nixos.services.openssh.enable = true;
        den.aspects.group.sub.b.nixos.services.timesyncd.enable = true;

        # ._ should only include a and b, not the nixos class key
        den.aspects.igloo.includes = [ den.aspects.group.sub._ ];

        expr = {
          ssh = igloo.services.openssh.enable;
          time = igloo.services.timesyncd.enable;
          hostName = igloo.networking.hostName;
        };
        expected = {
          ssh = true;
          time = true;
          hostName = "nixos"; # class key must not leak
        };
      }
    );

    # Nested ._ skips class keys, same as root ._
    test-include-children-nested-skips-class-keys = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.group.sub = {
          nixos.networking.hostName = "should-not-leak";
          child.nixos.services.openssh.enable = true;
        };

        den.aspects.igloo.includes = [ den.aspects.group.sub._ ];

        expr = {
          ssh = igloo.services.openssh.enable;
          hostName = igloo.networking.hostName;
        };
        expected = {
          ssh = true;
          hostName = "nixos";
        };
      }
    );

    # Nested ._ excludes user-defined class keys
    test-include-children-nested-custom-class = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.os = {
          description = "Custom OS class";
          forwardTo = {
            class = "nixos";
            path = [ ];
          };
        };

        # sub has a custom class key (os) and a child aspect (svc)
        den.aspects.group.sub.os.networking.hostName = "from-os";
        den.aspects.group.sub.svc.nixos.services.openssh.enable = true;

        # ._ must include svc but not os
        den.aspects.igloo.includes = [ den.aspects.group.sub._ ];

        expr = {
          ssh = igloo.services.openssh.enable;
          hostName = igloo.networking.hostName;
        };
        expected = {
          ssh = true;
          hostName = "nixos"; # os class key must not leak through ._
        };
      }
    );

    # Nested ._ with parametric child aspects
    test-include-children-nested-parametric = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.group.sub.static.nixos.services.timesyncd.enable = true;
        den.aspects.group.sub.dynamic =
          { host, ... }:
          {
            nixos.services.openssh.enable = true;
          };

        den.aspects.igloo.includes = [ den.aspects.group.sub._ ];

        expr = {
          ssh = igloo.services.openssh.enable;
          time = igloo.services.timesyncd.enable;
        };
        expected = {
          ssh = true;
          time = true;
        };
      }
    );
  };
}
