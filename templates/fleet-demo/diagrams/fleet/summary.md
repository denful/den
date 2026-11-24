## Fleet Summary

A tabular overview of the fleet's resolved topology: environment
membership, aspect distribution per host, pipe producer/collector
relationships, and which policies fired during resolution. This is
the same data the diagrams above visualize, presented as text tables
for quick reference or machine consumption.

# Fleet Summary

## Topology

- **2** environments, **4** hosts, **5** users
- Scope chain: flake → fleet → user → host → environment → flake-system
- Trace entries: 249

## Environments

| Environment | Hosts | Host Count | Users |
| ------------- | ------- | ------------ | ------- |
| prod | lb-prod, web-prod-1, web-prod-2 | 3 | 3 |
| staging | web-staging | 1 | 2 |

## Aspects by Host

| Host | Aspect Count | Aspects |
| ------ | -------------- | --------- |
| lb-prod | 4 | haproxy, hostfile, hostname/os, lb-prod |
| web-prod-1 | 4 | hostfile, hostname/os, nginx, web-prod-1 |
| web-prod-2 | 4 | hostfile, hostname/os, nginx, web-prod-2 |
| web-staging | 4 | hostfile, hostname/os, nginx, web-staging |

## Pipes

| Pipe | Scope Boundary | Producers | Collectors |
| ------ | ---------------- | ----------- | ------------ |
| host-addrs | environment: prod | lb-prod, web-prod-1, web-prod-2 | lb-prod, web-prod-1, web-prod-2 |
| host-addrs | environment: staging | web-staging | web-staging |
| http-backends | environment: prod | web-prod-1, web-prod-2 | lb-prod |
| http-backends | environment: staging | web-staging | web-staging |

## Policies

| Policy | Fires at |
| -------- | ---------- |
| flake-to-systems | flake |
| to-fleet | flake |
| apps-to-flake | flake-system |
| checks-to-flake | flake-system |
| devShells-to-flake | flake-system |
| legacyPackages-to-flake | flake-system |
| packages-to-flake | flake-system |
| fleet-to-envs | fleet |
| env-to-hosts | environment |
| collect-backends | host |
| collect-host-addrs | host |
| host-to-hm-users | host |
| host-to-users | host |
| mutual-provider/transition-default | host |
| os-to-host | host |
| user-aspects(all)/transition-default | host |
| define-user-account | user |
| hm-user-detect | user |
| user-to-host | user |
