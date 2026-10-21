# Validation

Deployment and egress checks of the stack, run against a live subscription (East US) on two occasions. Subscription IDs and the real public IP are omitted.

## Run 1 - deployment (2026-10-19)

| | |
|---|---|
| Resources created | 57 (`Apply complete! Resources: 57 added`) |
| Duration | ~34 minutes (the hub and its connection are the slowest) |

## Run 1 - results

| Check | Result |
|---|---|
| Probe VMs without public IP in `snet-app` (private subnet, no default outbound) | `vm-app1-probe-z1` (zone 1) and `vm-app1-probe-z2` (zone 2), both `Succeeded` |
| Outbound IP seen from the internet (`curl https://ifconfig.me`) | Both VMs return `<NAT_PUBLIC_IP>`, equal to the NAT Gateway IP |
| HTTPS burst (12 requests to microsoft.com per VM) | 24 of 24 HTTP 200, ~80 ms average, MTU 1500 |
| Plain HTTP (example.com, 6 per VM) | 12 of 12 HTTP 200 |
| Varied burst (microsoft, github, google, aws, terraform registry, ifconfig; 8 per site) | 48 of 48 per VM (96 of 96) |
| NIC effective routes | `0.0.0.0/0` and `10.251.0.0/24` with source *VirtualNetworkGateway* (injected by the hub); no UDR on the subnet |
| Hub | `conn-app1` with `internet security = True`, `conn-egress` with `False`; `rt-spokes` holds `0.0.0.0/0` and the egress prefix |
| Firewall | `Succeeded`, 3 zones, Standard; `AZFWNetworkRule` logs show both VMs' traffic as `Allow` under `allow-all-outbound` (the rule set at that time) |
| NAT Gateway | `StandardV2`, attached only to `AzureFirewallSubnet` |

## Run 1 - observations

Within the first minutes after the VMs were created, the zone 2 VM had one slow request (18.6 s) and two of three repeats that hit the 30 s timeout, with the TCP connection opening in milliseconds. It did not reproduce in the following 144 requests, and its cause was not identified.

## Run 2 - application rules, categories, DNS (2026-10-21)

Deployed with the domain-level application rules, threat intelligence in `Deny`, DNS proxy and Policy Analytics enabled: 59 resources in ~36 minutes.

| Check | Result |
|---|---|
| Egress IP from both zones | Both VMs return the NAT Gateway IP |
| HTTPS burst right after deployment | Zone 1: 17 of 20 (3 timeouts of 8 s); zone 2: 20 of 20 |
| HTTPS burst 2-3 minutes later | 30 of 30 on each VM (60 of 60) |
| HTTP (`example.com`) and HTTPS with SNI (`one.one.one.one`) | HTTP 200 |
| HTTPS without SNI (bare IP `1.1.1.1`) | Denied; log reason `SNI TLS extension was missing` |
| Non-web ports (TCP 8080, TCP 22) and ICMP | Allowed by `allow-tcp-non-web` / `allow-icmp` |
| Private destination (`172.16.5.5:80`) | Denied by `deny-rfc1918`, logged in `AZFWNetworkRule` |
| Threat intelligence (Microsoft indicator domain) | Blocked (HTTP 470); `AZFWThreatIntel` logs `Deny` with the threat description |
| Domain visibility | `AZFWApplicationRule` lists every domain (for example `www.microsoft.com`, `ifconfig.me`, `github.com`) under `allow-all-web` |
| Web category `Gambling` on Standard | Betting sites blocked; log shows rule `deny-categories` and `WebCategory = Gambling`; microsoft.com and github.com stay allowed |
| Categories `ChildAbuseImages`, `CriminalActivity`, `IllegalSoftware` | Accepted by the API and read back from the policy |
| DNS through the firewall (VNet DNS = `10.251.0.4`) | VMs use the firewall as resolver, names resolve, HTTPS works; queries appear in `AZFWDnsQuery` |
| Policy in Azure | `fwp-egress`: Standard, threat intelligence `Deny`, DNS proxy and analytics enabled, 3 zones |
| NIC effective routes | `0.0.0.0/0` via `VirtualNetworkGateway` `10.250.0.68` (hub router), no UDR on the subnet |

### Network Watcher

The regional Network Watcher answers live diagnostics with no extra configuration; there are no flow logs or connection monitors for this stack.

| Diagnostic from `vm-app1-probe-z1` | Result |
|---|---|
| Next hop to `8.8.8.8` and to `172.16.5.5` | `VirtualNetworkGateway` (`10.250.0.68`, Gateway Route): the hub |
| Next hop to an address inside `app1` | `VirtualNetwork` (System Route) |
| IP flow verify, outbound TCP to `8.8.8.8:443` | `Allow` by `Allow-All-Outbound` |

### Observations

- The intermittent stalls reproduced in the first minutes after deployment, this time on zone 1 (3 of 20 requests), so they are not specific to a zone. Both VMs were clean from the second round on (60 of 60). Cause not identified; consistent with a warm-up period of the new firewall or hub.
- Policy Analytics had no aggregated data yet: the aggregation tables fill hourly.
- QUIC (UDP 443) could not be tested because the VM's `curl` has no HTTP/3 support.
- `app1_dns_via_firewall` has no effect on an existing VNet (see `firewall.md`).

## Not covered

- Isolation between spokes (only `app1` exists).
- Inbound through the public subnets (no Application Gateway or load balancer deployed).
- AKS, Container Apps and Function inside `app1` (the subnets exist, the services do not).
