## Fleet Summary

A tabular overview of the fleet's resolved topology: environment
membership, aspect distribution per host, pipe producer/collector
relationships, and which policies fired during resolution. This is
the same data the diagrams above visualize, presented as text tables
for quick reference or machine consumption.

# Fleet Summary

## Topology

- **2** environments, **4** hosts, **5** users
- Scope chain: flake → flake-system → fleet → user → host → environment
- Trace entries: 245

## Environments

| Environment | Hosts | Host Count | Users |
| ------------- | ------- | ------------ | ------- |
| prod | lb-prod, web-prod-1, web-prod-2 | 3 | 3 |
| staging | web-staging | 1 | 2 |

## Aspects by Host

| Host | Aspect Count | Aspects |
| ------ | -------------- | --------- |
| lb-prod | 5 | haproxy, hostfile, insecure-predicate/os, lb-prod, unfree-predicate/os |
| web-prod-1 | 5 | hostfile, insecure-predicate/os, nginx, unfree-predicate/os, web-prod-1 |
| web-prod-2 | 5 | hostfile, insecure-predicate/os, nginx, unfree-predicate/os, web-prod-2 |
| web-staging | 5 | hostfile, insecure-predicate/os, nginx, unfree-predicate/os, web-staging |

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
| to-fleet | flake |
| to-systems | flake |
| fleet-to-envs | fleet |
| env-to-hosts | environment |
| collect-backends | host |
| collect-host-addrs | host |
| env-users | host |
| os-to-host | host |
| user-to-host | user |
| to-apps | flake-system |
| to-checks | flake-system |
| to-devShells | flake-system |
| to-legacyPackages | flake-system |
| to-packages | flake-system |
