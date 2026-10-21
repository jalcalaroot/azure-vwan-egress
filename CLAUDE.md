# azure-vwan-egress

Centralized internet egress with Azure Virtual WAN. The design and its reasoning are in `docs/design.md`; firewall details in `docs/firewall.md`; what application VNets must do to use the egress in `docs/spoke-contract.md`; test results in `docs/validation.md`.

## Working conventions

- Show each command and wait for confirmation before creating or changing cloud resources.
- No real identifiers (subscription, tenant, account IDs) or e-mail addresses in versioned files: use placeholders such as `<SUBSCRIPTION_ID>`.
- Commits use the GitHub noreply address.
- NSG egress is open by design (`Allow-All-Outbound`). The firewall policy is also open for outbound traffic: web traffic is allowed to any domain and logged by domain; any restriction must be requested explicitly.

## Key facts (verified against Microsoft documentation)

- A NAT Gateway is not supported in a Virtual WAN hub or secured hub, cannot span VNets and cannot be the next hop of another VNet, hence `vnet-egress`.
- StandardV2 NAT Gateway: no `zones`; its public IP must be StandardV2 (`# tflint-ignore: azurerm_public_ip_invalid_sku`).
- The firewall needs its own Standard public IP even though egress leaves through the NAT Gateway.
- The connection that advertises `0.0.0.0/0` has `internet_security_enabled = false`; spoke connections use `true`.
- `0.0.0.0/0` does not propagate between hubs.
- Network rules are evaluated before application rules; a network rule covering 80/443 would make the application rules unreachable.
- x86 B-series VM sizes are not available in this subscription (`NotAvailableForSubscription`); the test VMs use `Standard_D2as_v4`.
- A single shared resource group is used, so `app1` resources carry the `app1` suffix.
- The firewall keeps explicit `zones = ["1","2","3"]` (valid and zone-redundant; Microsoft recommends omitting `zones` on new firewalls).

## Status

Deployed and validated (see `docs/validation.md`). Cost while deployed is about US$1.7/hour, so it is created on demand and destroyed afterwards; the hub takes ~35 minutes.

## Backlog

- Verify the application rules after deployment: HTTPS without SNI, QUIC, and the `AZFWApplicationRule` logs.
- Test `app1_dns_via_firewall = true` (requires Private DNS zone links on `vnet-egress`).
- Alerts (health, SNAT utilization, threat intelligence hits).
- Exercise isolation between spokes with a second spoke; inbound through the public subnets; AKS, Container Apps and Function inside `app1`.
- CI (plan/apply workflows). CI identity permissions must live in a separate persistent root, not in the state of the stack they deploy.
- Run Checkov (not installed locally).
- Disaster recovery in a second region (own hub and egress VNet; `0.0.0.0/0` does not cross hubs).
