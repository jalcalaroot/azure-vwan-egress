# Azure Firewall

Azure Firewall Standard (3 availability zones) in `vnet-egress`, managed through the Firewall Policy `fwp-egress`. It acts as the SNAT point in front of the NAT Gateway, applies threat intelligence, and records every flow; web traffic is logged by domain.

## Rules

Network rules are evaluated before application rules and are terminating ([Rule processing](https://learn.microsoft.com/azure/firewall/rule-processing)), so the network rules deliberately exclude web ports.

| Order | Type | Rule | Effect |
|---|---|---|---|
| — | Threat intelligence (`Deny`) | Microsoft feed | Blocks traffic to/from known malicious IPs, domains and URLs before any rule runs |
| 100 | Network, Deny | `deny-rfc1918` | Spokes only reach the internet (`block_private_destinations`) |
| 200 | Network, Allow | `allow-tcp-non-web` (TCP 1-79, 81-442, 444-65535), `allow-udp-non-quic` (UDP 1-442, 444-65535), `allow-icmp` | Every other port and protocol stays open |
| 250 | Application, Deny | `deny-categories` (only if `denied_web_categories` is not empty) | Blocks the configured web categories (requires Premium) |
| 300 | Application, Allow | `allow-all-web` (HTTP 80 and HTTPS 443, FQDN `*`) | Allows web traffic and logs it by domain in `AZFWApplicationRule` |

Behavior to be aware of:

- HTTPS is matched by SNI. An HTTPS connection without SNI (for example, to a bare IP) matches no rule and is denied.
- UDP 443 (QUIC / HTTP/3) is not allowed, so it cannot bypass the per-domain logging; clients fall back to TCP 443.
- For HTTP the firewall resolves the host with its own DNS and drops traffic if the port in the Host header does not match.
- TCP idle timeout towards the internet is 4 minutes by default ([TCP session behavior](https://learn.microsoft.com/azure/firewall/tcp-session-behavior)).
- If the firewall is deallocated and reallocated its private IP may change, and the hub's static route targets that IP.

## Configuration against Microsoft's recommendations

Sources: [Architecture best practices for Azure Firewall](https://learn.microsoft.com/azure/well-architected/service-guides/azure-firewall), [Secure your Azure Firewall deployment](https://learn.microsoft.com/azure/firewall/secure-firewall), [Best practices for performance](https://learn.microsoft.com/azure/firewall/firewall-best-practices).

| Recommendation | Status |
|---|---|
| Availability zones | Done (3 zones) |
| Firewall Policy managed as code | Done |
| Dedicated `AzureFirewallSubnet` (/26) | Done |
| Structured, resource-specific logs (`AZFW*` tables) in Log Analytics | Done |
| NAT Gateway to avoid SNAT port exhaustion | Done (64,512 ports per IP versus 2,496) |
| Network security groups, not the firewall, for intra-VNet traffic | Done |
| Threat intelligence in alert-and-deny mode | Done (`Deny`). In `Alert` mode a network rule on 80/443 masks the alerts ([known issue](https://learn.microsoft.com/troubleshoot/azure/firewall/firewall-known-issues)) |
| DNS proxy | Enabled in the policy; clients use it only when their VNet DNS points to the firewall (`app1_dns_via_firewall`) |
| Policy Analytics | Enabled (`insights` block). It analyzes only what happens after it is enabled; data takes ~60 minutes to appear |
| Application rules with FQDN visibility | Done (`allow-all-web`) |
| Alerts on throughput, health state, SNAT port utilization, latency probe and threat intelligence hits | Not configured |
| Web categories | Prepared (`denied_web_categories`), empty: the azurerm provider documents them as Premium-only |
| IDPS, TLS inspection, URL filtering | Premium only |
| Customer-controlled maintenance | Not configured |

## DNS proxy

Using the firewall as DNS requires three steps ([DNS settings](https://learn.microsoft.com/azure/firewall/dns-settings)): enable the proxy in the policy (done), choose the upstream servers (Azure DNS by default), and point the VNet DNS servers to the firewall's private IP (`app1_dns_via_firewall = true`).

The firewall forwards to Azure DNS from `vnet-egress`, so Private DNS zones (`privatelink.*`) must also be linked to `vnet-egress`, or resolved through Azure DNS Private Resolver ([Private Link and DNS in Virtual WAN](https://learn.microsoft.com/azure/architecture/networking/guide/private-link-virtual-wan-dns-single-region-workload)). A VNet with private endpoints would stop resolving them otherwise.

## Possible enhancements

1. Alerts for health, SNAT utilization and threat intelligence hits (needs an action group).
2. `app1_dns_via_firewall = true` once the Private DNS zone links are in place.
3. Deny high-risk web categories (for example *Child abuse images*, *Criminal activity*, *Illegal software*) or evaluate Premium for IDPS.
4. Restrict egress with an allow-list using FQDN tags and domains, if the environment requires closed egress.
