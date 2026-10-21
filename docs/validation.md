# Validation

Deployment and egress tests of the stack, run against a live subscription (East US). Subscription IDs and the real public IP are omitted.

## Deployment (2026-10-19)

| | |
|---|---|
| Resources created | 57 (`Apply complete! Resources: 57 added`) |
| Duration | ~34 minutes (the hub and its connection are the slowest) |

## Results

| Test | Result |
|---|---|
| Test VMs without public IP in `snet-app` (private subnet, no default outbound) | `vm-app1-test-z1` (zone 1) and `vm-app1-test-z2` (zone 2), both `Succeeded` |
| Outbound IP seen from the internet (`curl https://ifconfig.me`) | Both VMs return `<NAT_PUBLIC_IP>`, equal to the NAT Gateway IP |
| HTTPS burst (12 requests to microsoft.com per VM) | 24 of 24 HTTP 200, ~80 ms average, MTU 1500 |
| Plain HTTP (example.com, 6 per VM) | 12 of 12 HTTP 200 |
| Varied burst (microsoft, github, google, aws, terraform registry, ifconfig; 8 per site) | 48 of 48 per VM (96 of 96) |
| NIC effective routes | `0.0.0.0/0` and `10.251.0.0/24` with source *VirtualNetworkGateway* (injected by the hub); no UDR on the subnet |
| Hub | `conn-app1` with `internet security = True`, `conn-egress` with `False`; `rt-spokes` holds `0.0.0.0/0` and the egress prefix |
| Firewall | `Succeeded`, 3 zones, Standard; `AZFWNetworkRule` logs show both VMs' traffic as `Allow` under `allow-all-outbound` (the rule set at that time) |
| NAT Gateway | `StandardV2`, attached only to `AzureFirewallSubnet` |

## Observations

Within the first minutes after the VMs were created, the zone 2 VM had one slow request (18.6 s) and two of three repeats that hit the 30 s timeout, with the TCP connection opening in milliseconds. It did not reproduce in the following 144 requests, and its cause was not identified.

## Not covered

- Isolation between spokes (only `app1` exists).
- Inbound through the public subnets (no Application Gateway or load balancer deployed).
- AKS, Container Apps and Function inside `app1` (the subnets exist, the services do not).
