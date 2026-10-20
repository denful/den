## Aspect Namespace

The global registry of all declared aspects and their hierarchy.
Each node is an aspect — a reusable unit of configuration that can
be included by hosts or users. Edges show the `includes` relationship:
`lb-prod` includes `haproxy` and `hostfile`, web servers include
`nginx` and `hostfile`.

```mermaid
graph TD
  aspects([aspects]):::root
  haproxy["haproxy · shared"]:::haproxy_c
  hostfile["hostfile · shared"]:::hostfile_c
  lb_prod["lb-prod · host"]:::lb_prod_c
  nginx["nginx · shared"]:::nginx_c
  web_prod_1["web-prod-1 · host"]:::web_prod_1_c
  web_prod_2["web-prod-2 · host"]:::web_prod_2_c
  web_staging["web-staging · host"]:::web_staging_c

  aspects --> lb_prod
  aspects --> web_prod_1
  aspects --> web_prod_2
  aspects --> web_staging
  lb_prod --> haproxy
  lb_prod --> hostfile
  web_prod_1 --> nginx
  web_prod_1 --> hostfile
  web_prod_2 --> nginx
  web_prod_2 --> hostfile
  web_staging --> nginx
  web_staging --> hostfile

  classDef root fill:#218bff,stroke:#218bff,color:#1f2328,font-weight:bold
  classDef haproxy_c fill:#e16f24,stroke:#e16f24,color:#1f2328,stroke-width:2px
  classDef hostfile_c fill:#e16f24,stroke:#e16f24,color:#1f2328,stroke-width:2px
  classDef lb_prod_c fill:#218bff,stroke:#218bff,color:#1f2328,stroke-width:2px
  classDef nginx_c fill:#e16f24,stroke:#e16f24,color:#1f2328,stroke-width:2px
  classDef web_prod_1_c fill:#218bff,stroke:#218bff,color:#1f2328,stroke-width:2px
  classDef web_prod_2_c fill:#218bff,stroke:#218bff,color:#1f2328,stroke-width:2px
  classDef web_staging_c fill:#218bff,stroke:#218bff,color:#1f2328,stroke-width:2px
```
