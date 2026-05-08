# Server resource aspect — generates an hcloud_server per host.
#
# Each host including this aspect gets a Terraform resource that
# provisions a Hetzner Cloud server using the host's schema fields.
#
# The aspect is parametric ({ host, ... }:) with a host-qualified name
# so each host scope produces a uniquely-keyed terranix module.
{ ... }:
let
  serverAspect =
    { host, ... }:
    {
      name = "hcloud-server/${host.name}";
      terranix = {
        resource.hcloud_server.${host.name} = {
          name = host.hostName;
          server_type = host.server-type;
          location = host.region;
          image = host.image;

          labels = {
            managed-by = "den-terranix";
          };
        };

        output."${host.name}_ip" = {
          value = "\${hcloud_server.${host.name}.ipv4_address}";
          description = "Public IPv4 of ${host.hostName}";
        };
      };
    };
in
{
  den.default.includes = [ serverAspect ];
}
