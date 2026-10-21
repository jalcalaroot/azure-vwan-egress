# azure-vwan-egress

Centralized internet egress for application VNets using **Azure Virtual WAN**: every private subnet leaves through one Azure Firewall behind a zone-redundant **NAT Gateway (StandardV2)**, while inbound traffic keeps entering through each VNet's own public subnets. Includes `app1`, a VNet with the same layers as [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network) but no NAT of its own, with a test VM per availability zone. Standalone Terraform project — own backend, own state.

## Architecture

```
                           Internet
                               │ inbound (public, appgw, apim)
                               ▼
┌─ app1 · vnet-app1 10.1.0.0/16 · no NAT of its own ─────────────────┐
│ entry:    snet-public · snet-appgw · snet-apim   (0/0 → Internet)  │
│ private:  snet-app · snet-aks · snet-privatelink ·                 │
│           snet-containerapps · snet-func · snet-aks-virtual-nodes  │
│ data:     snet-data   (0/0 → None, no internet)                    │
│                                                                    │
│ snet-app 10.1.8.0/22, test instances (no public IP):               │
│    vm-app1-test-z1 (zone 1) · vm-app1-test-z2 (zone 2)             │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 0/0 learned from the hub (no UDR)
┌─ Virtual WAN Standard ───────▼─────────────────────────────────────┐
│ virtual hub 10.250.0.0/23  ·  rt-spokes  ·  rt-egress              │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ static route 0/0 → 10.251.0.4
┌─ vnet-egress 10.251.0.0/24 ──▼─────────────────────────────────────┐
│ Azure Firewall Standard (3 zones) 10.251.0.4                       │
│    │ SNAT                                                          │
│    ▼                                                               │
│ NAT Gateway StandardV2 (zone-redundant, static public IP)          │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ outbound (NAT public IP)
                               ▼
                           Internet
```

A NAT Gateway cannot sit in a Virtual WAN hub or receive traffic from another VNet, so the egress lives in its own VNet behind the hub ([Azure NAT Gateway FAQ](https://learn.microsoft.com/azure/nat-gateway/faq)). The hub's `rt-spokes` carries the `0.0.0.0/0` route to the firewall, so spokes cannot see each other.

## Resources deployed

| Resource | Purpose | Docs |
|---|---|---|
| Virtual WAN (Standard) + virtual hub | Transit service; `rt-spokes` / `rt-egress` route tables, static `0.0.0.0/0` on the egress connection | [Virtual WAN](https://learn.microsoft.com/azure/virtual-wan/virtual-wan-about), [Hub routing](https://learn.microsoft.com/azure/virtual-wan/about-virtual-hub-routing) |
| Azure Firewall (Standard, 3 zones) + Firewall Policy | SNAT, threat intelligence (`Deny`), DNS proxy, rules that log web traffic by domain, Policy Analytics | [Azure Firewall](https://learn.microsoft.com/azure/firewall/overview), [Rule processing](https://learn.microsoft.com/azure/firewall/rule-processing) |
| NAT Gateway (StandardV2) + public IP | The single, stable outbound IP for every spoke | [NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview) |
| `vnet-egress` | Holds `AzureFirewallSubnet` only | [VNet overview](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) |
| `app1` VNet + 10 subnets | Same layers as the known VNet, no own NAT; built on [`Azure/avm-res-network-virtualnetwork` v0.22.2](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/0.22.2) | [Default outbound access](https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access) |
| NSGs, route tables, ASGs (`app1`) | Per-subnet rules with explicit outbound allow; entry subnets keep direct internet | [NSG overview](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview) |
| Log Analytics Workspace | Firewall resource-specific logs (`AZFW*` tables) | [Firewall logs](https://learn.microsoft.com/azure/firewall/monitor-firewall) |
| 2 Linux VMs (`app1`, zones 1 and 2) | Test instances in `snet-app`, no public IP | [Availability zones](https://learn.microsoft.com/azure/reliability/availability-zones-overview) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged in via `az login` with Contributor-or-better on the subscription
- An existing resource group (`jalcalaroot` by default) and the shared tfstate storage account

## Usage

```bash
az login
export TF_VAR_subscription_id="<subscription-id>"

terraform init
terraform apply        # the hub takes ~35 minutes
```

Test the egress from both zones; each VM must return the NAT Gateway IP (`terraform output egress_public_ip`):

```bash
for z in 1 2; do
  az vm run-command invoke -g <resource-group> -n vm-app1-test-z$z --command-id RunShellScript \
    --scripts "curl -s --max-time 15 https://ifconfig.me" --query "value[0].message" -o tsv
done
```

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `subscription_id` | — | via `TF_VAR_subscription_id` |
| `resource_group_name` / `location` | `jalcalaroot` / `eastus` | Must support NAT Gateway StandardV2 |
| `hub_address_prefix` | `10.250.0.0/23` | |
| `egress_vnet_address_space` / `egress_firewall_subnet_cidr` | `10.251.0.0/24` / `10.251.0.0/26` | |
| `vnet_address_space` and `*_subnet_cidr` | `10.1.0.0/16` and the `10.1.x.x` layout | `app1`; address spaces must not overlap |
| `spoke_address_space` | `10.0.0.0/13` | Source range the firewall rules accept |
| `block_private_destinations` | `true` | Firewall denies RFC1918 destinations |
| `denied_web_categories` | `[]` | Needs Firewall Premium |
| `app1_dns_via_firewall` | `false` | Use the firewall as DNS (see the note in `variables.tf`) |
| `test_vm_size` / `test_vm_zones` | `Standard_D2as_v4` / `["1","2"]` | |
| `log_analytics_retention_days` | `30` | |

## Outputs

| Output | Description |
|---|---|
| `virtual_hub_id`, `route_table_spokes_id`, `route_table_egress_id` | What a spoke needs to connect ([`modules/spoke-connection`](modules/spoke-connection)) |
| `egress_public_ip` | Outbound public IP of every spoke |
| `firewall_private_ip` | Next hop of the `0.0.0.0/0` route |
| `app1_vnet_id`, `test_vm_names` | `app1` VNet and its test VMs |

## Cost

About US$1.7 per hour (~US$40 per day) while deployed, ~70% of it the firewall. Details, the firewall configuration and the validation results are in [`docs/`](docs/).
