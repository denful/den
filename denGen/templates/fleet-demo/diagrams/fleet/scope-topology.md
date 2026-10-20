## Scope Topology

The scope tree shows how den organizes entities hierarchically.
Each node is a scope — a context in which aspects and policies are
evaluated. Child scopes inherit their parent's context bindings.

In this fleet, the tree is: flake → fleet → environment → host → user.
Environment and host scopes are created by policies that walk the
`fleet.environments` and `den.hosts` registries. User scopes are
created by access policies that match registry users by group membership.

```mermaid
graph TD
  environment_prod_fleet_fleet[["environment: prod"]]
  environment_prod_fleet_fleet_host_lb_prod["host: lb-prod"]
  environment_prod_fleet_fleet_host_lb_prod_user_alice(["user: alice"])
  environment_prod_fleet_fleet_host_web_prod_1["host: web-prod-1"]
  environment_prod_fleet_fleet_host_web_prod_1_user_alice(["user: alice"])
  environment_prod_fleet_fleet_host_web_prod_2["host: web-prod-2"]
  environment_prod_fleet_fleet_host_web_prod_2_user_alice(["user: alice"])
  environment_staging_fleet_fleet[["environment: staging"]]
  environment_staging_fleet_fleet_host_web_staging["host: web-staging"]
  environment_staging_fleet_fleet_host_web_staging_user_alice(["user: alice"])
  environment_staging_fleet_fleet_host_web_staging_user_bob(["user: bob"])
  fleet_fleet(["fleet: fleet"])
  system_x86_64_linux["flake-system: system=x86_64-linux"]

  fleet_fleet --> environment_prod_fleet_fleet
  environment_prod_fleet_fleet --> environment_prod_fleet_fleet_host_lb_prod
  environment_prod_fleet_fleet_host_lb_prod --> environment_prod_fleet_fleet_host_lb_prod_user_alice
  environment_prod_fleet_fleet --> environment_prod_fleet_fleet_host_web_prod_1
  environment_prod_fleet_fleet_host_web_prod_1 --> environment_prod_fleet_fleet_host_web_prod_1_user_alice
  environment_prod_fleet_fleet --> environment_prod_fleet_fleet_host_web_prod_2
  environment_prod_fleet_fleet_host_web_prod_2 --> environment_prod_fleet_fleet_host_web_prod_2_user_alice
  fleet_fleet --> environment_staging_fleet_fleet
  environment_staging_fleet_fleet --> environment_staging_fleet_fleet_host_web_staging
  environment_staging_fleet_fleet_host_web_staging --> environment_staging_fleet_fleet_host_web_staging_user_alice
  environment_staging_fleet_fleet_host_web_staging --> environment_staging_fleet_fleet_host_web_staging_user_bob

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
