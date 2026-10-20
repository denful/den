# ssh-keys: provision authorized SSH keys for users.
#
# Reads user.ssh-keys from the registry-sourced user entity and sets
# openssh.authorizedKeys.keys on the corresponding OS user.
# Only fires in user scope — keys land only on hosts where policies granted access.
#
# Structured as a battery (like define-user) so that each user gets a
# unique aspect identity, preventing cross-user dedup in the pipeline.
{ ... }:
{
  den.aspects.ssh-keys = {
    description = "Provision authorized SSH keys from user registry";
    includes = [
      (
        { host, user }:
        {
          name = "ssh-keys/${user.userName}@${host.name}";
          nixos.users.users.${user.userName}.openssh.authorizedKeys.keys = user.ssh-keys;
        }
      )
    ];
  };
}
