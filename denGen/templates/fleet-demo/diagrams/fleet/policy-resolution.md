## Policy Resolution

Policies are functions that run at each scope and produce effects:
resolving child entities, providing configuration, or collecting data.
This diagram shows which policies fire at each scope level and what
they produce.

The arrows show the resolution chain — how `to-fleet` creates the
fleet scope, `fleet-to-envs` fans out environments, `env-to-hosts`
walks hosts, and `env-users`/`host-users` resolve registry users
onto their granted hosts.

```mermaid
graph TD
  environment_prod_fleet_fleet{{"environment: prod"}}
  environment_prod_fleet_fleet_host_lb_prod["host: lb-prod"]
  environment_prod_fleet_fleet_host_lb_prod_user_alice(["user: alice"])
  environment_prod_fleet_fleet_host_web_prod_1["host: web-prod-1"]
  environment_prod_fleet_fleet_host_web_prod_1_user_alice(["user: alice"])
  environment_prod_fleet_fleet_host_web_prod_2["host: web-prod-2"]
  environment_prod_fleet_fleet_host_web_prod_2_user_alice(["user: alice"])
  environment_staging_fleet_fleet{{"environment: staging"}}
  environment_staging_fleet_fleet_host_web_staging["host: web-staging"]
  environment_staging_fleet_fleet_host_web_staging_user_alice(["user: alice"])
  environment_staging_fleet_fleet_host_web_staging_user_bob(["user: bob"])
  fleet_fleet(["fleet: fleet"])
  system_x86_64_linux["flake-system: system=x86_64-linux"]

  fleet_fleet -->|fleet-to-envs| environment_prod_fleet_fleet
  environment_prod_fleet_fleet -->|env-to-hosts| environment_prod_fleet_fleet_host_lb_prod
  environment_prod_fleet_fleet_host_lb_prod -->|collect-backends, collect-host-addrs, env-users, os-to-host| environment_prod_fleet_fleet_host_lb_prod_user_alice
  environment_prod_fleet_fleet -->|env-to-hosts| environment_prod_fleet_fleet_host_web_prod_1
  environment_prod_fleet_fleet_host_web_prod_1 -->|collect-backends, collect-host-addrs, env-users, os-to-host| environment_prod_fleet_fleet_host_web_prod_1_user_alice
  environment_prod_fleet_fleet -->|env-to-hosts| environment_prod_fleet_fleet_host_web_prod_2
  environment_prod_fleet_fleet_host_web_prod_2 -->|collect-backends, collect-host-addrs, env-users, os-to-host| environment_prod_fleet_fleet_host_web_prod_2_user_alice
  fleet_fleet -->|fleet-to-envs| environment_staging_fleet_fleet
  environment_staging_fleet_fleet -->|env-to-hosts| environment_staging_fleet_fleet_host_web_staging
  environment_staging_fleet_fleet_host_web_staging -->|collect-backends, collect-host-addrs, env-users, os-to-host| environment_staging_fleet_fleet_host_web_staging_user_alice
  environment_staging_fleet_fleet_host_web_staging -->|collect-backends, collect-host-addrs, env-users, os-to-host| environment_staging_fleet_fleet_host_web_staging_user_bob

  style environment_prod_fleet_fleet fill:#a475f9,stroke:#a475f9,color:#1f2328
  style environment_prod_fleet_fleet_host_lb_prod fill:#2da44e,stroke:#2da44e,color:#1f2328
  style environment_prod_fleet_fleet_host_lb_prod_user_alice fill:#e16f24,stroke:#e16f24,color:#1f2328
  style environment_prod_fleet_fleet_host_web_prod_1 fill:#2da44e,stroke:#2da44e,color:#1f2328
  style environment_prod_fleet_fleet_host_web_prod_1_user_alice fill:#e16f24,stroke:#e16f24,color:#1f2328
  style environment_prod_fleet_fleet_host_web_prod_2 fill:#2da44e,stroke:#2da44e,color:#1f2328
  style environment_prod_fleet_fleet_host_web_prod_2_user_alice fill:#e16f24,stroke:#e16f24,color:#1f2328
  style environment_staging_fleet_fleet fill:#a475f9,stroke:#a475f9,color:#1f2328
  style environment_staging_fleet_fleet_host_web_staging fill:#2da44e,stroke:#2da44e,color:#1f2328
  style environment_staging_fleet_fleet_host_web_staging_user_alice fill:#e16f24,stroke:#e16f24,color:#1f2328
  style environment_staging_fleet_fleet_host_web_staging_user_bob fill:#e16f24,stroke:#e16f24,color:#1f2328
  style fleet_fleet fill:#218bff,stroke:#218bff,color:#1f2328
  style system_x86_64_linux fill:#339D9B,stroke:#339D9B,color:#1f2328
```
