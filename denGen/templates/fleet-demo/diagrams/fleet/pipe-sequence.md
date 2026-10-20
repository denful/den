## Pipe Sequence

A sequence diagram showing the emit → collect flow for each pipe.
Each host that participates in a pipe is shown as a lifeline, with
arrows indicating data flow direction.

> **Note:** The ordering of emitters in this diagram is arbitrary —
> `pipe.collect` gathers all peer emissions as an unordered list.
> The sequence is for visualization only; there is no guaranteed
> evaluation order between sibling hosts.

```mermaid
sequenceDiagram
    box prod
    participant lb_prod as lb-prod
    participant web_prod_1 as web-prod-1
    participant web_prod_2 as web-prod-2
    end
    box staging
    participant web_staging as web-staging
    end

    Note over lb_prod: hostfile → host-addrs
    Note over web_prod_1: hostfile → host-addrs
    Note over web_prod_2: hostfile → host-addrs
    Note over web_staging: hostfile → host-addrs
    web_prod_1 -->> lb_prod: host-addrs
    web_prod_2 -->> lb_prod: host-addrs
    lb_prod -->> web_prod_1: host-addrs
    web_prod_2 -->> web_prod_1: host-addrs
    lb_prod -->> web_prod_2: host-addrs
    web_prod_1 -->> web_prod_2: host-addrs

    Note over web_prod_1: nginx → http-backends
    Note over web_prod_2: nginx → http-backends
    Note over web_staging: nginx → http-backends
    web_prod_1 -->> lb_prod: http-backends
    web_prod_2 -->> lb_prod: http-backends
```
