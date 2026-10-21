# Design: centralized internet egress with Virtual WAN

## Requirement

Application VNets have no NAT Gateway of their own. All their internet egress goes through one highly available point with stable outbound IPs, while inbound traffic keeps entering through each VNet's own public subnets.

## Constraint that shapes the design

A NAT Gateway cannot be placed in a Virtual WAN hub (nor in the `AzureFirewallSubnet` of a secured hub), cannot span virtual networks, and cannot be the next hop of another VNet. It only performs NAT for traffic originating in the subnets it is attached to. Microsoft documents the hub-and-spoke pattern as a forwarder (Azure Firewall or an NVA) in front of the NAT Gateway:

- [NAT Gateway resource](https://learn.microsoft.com/azure/nat-gateway/nat-gateway-resource) and [FAQ](https://learn.microsoft.com/azure/nat-gateway/faq)
- [Tutorial: NAT gateway with Azure Firewall in a hub-and-spoke network](https://learn.microsoft.com/azure/nat-gateway/tutorial-hub-spoke-nat-firewall)
- [Scale SNAT ports with Azure NAT Gateway](https://learn.microsoft.com/azure/firewall/integrate-with-nat-gateway)

The egress therefore lives in its own VNet connected to the hub.

| Option | NAT Gateway | Firewall management | Chosen |
|---|---|---|---|
| A. Secured hub (Azure Firewall in the hub + routing intent) | No (only firewall public IPs, up to 80) | Microsoft-managed, automatic routes | No |
| **B. Egress VNet: Azure Firewall + StandardV2 NAT Gateway, static `0.0.0.0/0` on the hub connection** | **Yes** | Explicit routes | **Yes** |
| C. Classic hub-and-spoke with VNet peering (no Virtual WAN) | Yes | Explicit routes | No |

Option A is simpler to operate but gives up the NAT Gateway (stable IPs, 64,512 SNAT ports per IP).

## Routing model

No routing intent. Two custom route tables in the hub:

| Route table | Associated with | Contains | Effect |
|---|---|---|---|
| `rt-spokes` | every application VNet | `0.0.0.0/0 → firewall` (published by the egress connection) and the egress VNet prefix | Spokes leave through the firewall and do not see each other |
| `rt-egress` | the egress connection | the prefix of every spoke (propagated) | The firewall can return the replies |

Settings required by Microsoft ([Securing internet access](https://learn.microsoft.com/azure/virtual-wan/about-internet-routing)):

- The egress connection has `internet_security_enabled = false` (the connection that advertises `0.0.0.0/0` must not receive it).
- Spoke connections have `internet_security_enabled = true` (that is what makes them learn `0.0.0.0/0`).
- The static `0.0.0.0/0` does not propagate between hubs: every hub/region needs its own egress VNet.
- The static route targets the firewall's private IP, never the hub router IPs.

## High availability

| Component | How |
|---|---|
| Virtual hub / router | Microsoft-managed |
| Azure Firewall | 3 availability zones |
| NAT Gateway | StandardV2: zone-redundant by design (`zones` omitted), StandardV2 public IP |

A single hub does not survive a regional outage; disaster recovery would need a second hub and egress VNet in another region.

## Application VNet `app1`

`app1` (`10.1.0.0/16`) lives in this repository (`app1_*.tf`) and has the same ten layers as the [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network) VNet — public, appgw, app, data, aks, privatelink, containerapps, aks-virtual-nodes, func and apim — each with its NSG (`nsg-app1-snet-*`, explicit outbound allow) and seven ASGs (`asg-app1-*`).

| | Known VNet | `app1` |
|---|---|---|
| Own NAT Gateway | Yes | **No**: egress goes through the hub |
| Private subnets (app, data, aks, privatelink) | NAT Gateway | `0.0.0.0/0` learned from the hub (`data` keeps no internet: `0/0 → None`) |
| Inbound subnets (public, appgw, apim) | `public` with `0/0 → Internet`; appgw/apim without route table | all three with a `0/0 → Internet` route table |
| Names | `nsg-snet-*`, `rt-*`, `asg-*` | `app1` suffix (single shared resource group) |

`snet-app` hosts two probe VMs, one per availability zone (`vm-app1-probe-z1`, `vm-app1-probe-z2`), without public IP. Azure subnets span every zone ([Reliability in Azure Virtual Network](https://learn.microsoft.com/azure/reliability/reliability-virtual-network)), so both share the subnet. Their internet access can only go through app1 → hub → firewall → NAT Gateway.

## Firewall

Rules, threat intelligence, DNS proxy and monitoring are described in [firewall.md](firewall.md).

## Scope

- One application VNet (`app1`); more are attached with [`modules/spoke-connection`](../modules/spoke-connection) following [spoke-contract.md](spoke-contract.md). Isolation between spokes needs a second spoke to be exercised.
- Centralized private DNS is out of scope: `privatelink.*` zones stay linked per VNet.
- No CI/CD yet.

## Cost

List prices, East US (Azure Retail Prices API):

| Component | Price | Monthly (730 h) |
|---|---|---|
| Azure Firewall Standard | US$1.25/h | ~US$912 |
| Virtual WAN Standard hub | US$0.25/h | ~US$183 |
| NAT Gateway StandardV2 | US$4/month | US$4 |
| Public IPs (2) and Log Analytics | a few cents/h | ~US$10-15 |
| Two probe VMs (`Standard_D2as_v4`) | ~US$0.1/h each | ~US$140 |
| **Total without traffic** | **~US$1.7/h (~US$40/day)** | **~US$1,250** |

Data processing is charged per GB on the hub (US$0.02/GB), firewall and NAT Gateway. The firewall is about 70% of the cost; Premium (US$1.75/h) adds IDPS, TLS inspection and full-URL filtering. The hub takes ~35 minutes to create, so the stack is meant to be deployed on demand.
