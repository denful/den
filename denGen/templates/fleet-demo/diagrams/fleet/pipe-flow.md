## Pipe Flow

Pipes (quirks declared with `pipe.collect`) allow sibling hosts to
share data. Each host that includes an aspect emitting a quirk
contributes to a collected dataset available to peers in the same
environment.

This diagram shows two pipes in the fleet:
- **http-backends** — nginx aspects emit backend addresses, collected
  by the haproxy aspect on `lb-prod` to generate load balancer config.
- **host-addrs** — every host emits its address, collected by the
  hostfile aspect to generate `/etc/hosts` entries.

```mermaid
graph LR
  subgraph env_prod["prod"]
    lb_prod(["lb-prod (hostfile→host-addrs)"])
    web_prod_1(["web-prod-1 (nginx→http-backends, hostfile→host-addrs)"])
    web_prod_2(["web-prod-2 (nginx→http-backends, hostfile→host-addrs)"])
  end
  subgraph env_staging["staging"]
    web_staging(["web-staging (nginx→http-backends, hostfile→host-addrs)"])
  end

  web_prod_1 -->|http-backends| lb_prod
  web_prod_2 -->|http-backends| lb_prod
  web_prod_1 -->|host-addrs| lb_prod
  web_prod_2 -->|host-addrs| lb_prod
  lb_prod -->|host-addrs| web_prod_1
  web_prod_2 -->|host-addrs| web_prod_1
  lb_prod -->|host-addrs| web_prod_2
  web_prod_1 -->|host-addrs| web_prod_2

  linkStyle 0 stroke:#fa4549,stroke-width:2px
  linkStyle 1 stroke:#fa4549,stroke-width:2px
  linkStyle 2 stroke:#2da44e,stroke-width:2px
  linkStyle 3 stroke:#2da44e,stroke-width:2px
  linkStyle 4 stroke:#2da44e,stroke-width:2px
  linkStyle 5 stroke:#2da44e,stroke-width:2px
  linkStyle 6 stroke:#2da44e,stroke-width:2px
  linkStyle 7 stroke:#2da44e,stroke-width:2px

  style lb_prod fill:#2da44e,stroke:#2da44e,color:#1f2328
  style web_prod_1 fill:#2da44e,stroke:#2da44e,color:#1f2328
  style web_prod_2 fill:#2da44e,stroke:#2da44e,color:#1f2328
  style web_staging fill:#2da44e,stroke:#2da44e,color:#1f2328
  style env_prod fill:transparent,stroke:#8c959f,stroke-width:1px
  style env_staging fill:transparent,stroke:#8c959f,stroke-width:1px
```
