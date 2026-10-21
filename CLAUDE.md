# azure-vwan-egress

Salida centralizada a internet con Virtual WAN. Diseño y razones en `docs/design.md`; lo que deben cumplir las VNets de aplicación en `docs/spoke-contract.md`.

## Reglas del propietario

- Salida de los **NSG** abierta: decisión del propietario ("la salida debe estar abierta").
- Salida del **firewall** abierta (sin filtrado por dominio ni categoría): **supuesto mío, no una decisión del propietario**. Está pendiente decidir si el firewall debe filtrar. No cerrarla sin que lo pida.
- La inteligencia de amenazas en `Deny` solo bloquea destinos maliciosos conocidos y fue aprobada por el propietario (2026-10-21).
- Mostrar cada comando y esperar confirmación antes de crear o modificar recursos en la nube.
- Sin IDs reales (suscripción, tenant, cuentas) ni correos en archivos versionados: marcadores como `<SUBSCRIPTION_ID>`.
- Los commits usan el correo noreply de GitHub.

## Cuenta

- Los B-series x86 (B1s, B2s...) están `NotAvailableForSubscription` en eastus; la VM de prueba usa `Standard_D2as_v4` (cuota 10).
- Un solo resource group compartido: los recursos de `app1` llevan sufijo `app1` para no chocar con otras VNets.

## Decisiones

- El firewall mantiene `zones = ["1","2","3"]` explícito (válido y zona-redundante). Microsoft recomienda omitir `zones` en firewalls nuevos, pero el propietario decidió dejarlo así (2026-10-21).

## Hechos clave (verificados en la documentación de Microsoft)

- El NAT Gateway no está soportado en el hub de vWAN ni en el secured hub; por eso existe `vnet-egress`.
- NAT Gateway StandardV2: sin `zones`; su IP pública debe ser StandardV2 (`# tflint-ignore: azurerm_public_ip_invalid_sku`).
- El firewall necesita su propia IP pública Standard aunque la salida use el NAT.
- La conexión que anuncia el 0/0 lleva `internet_security_enabled = false`; las de los spokes `true`.
- El 0/0 no se propaga entre hubs.

## Estado

Desplegado y probado el 2026-10-19; **destruido** el mismo día (Azure verificado en 0). Evidencia en `docs/evidencia.md`. Para volver a probar: `terraform apply` (~35 min por el hub, ~US$1,6/h) y destruir al terminar.

## Validado

`terraform validate`, `tflint`, `plan` (57 recursos) y despliegue real: las 2 VMs de `app1` (zonas 1 y 2) salen a internet con la IP del NAT Gateway pasando por el firewall (logs `Allow`). Pendiente de explicar: cuelgues puntuales en los primeros minutos desde la zona 2 (ver evidencia).

## Pendiente

- Revisión del firewall hecha el 2026-10-21 (ver `docs/firewall-review.md`): inteligencia de amenazas en `Deny` y DNS proxy activado en la política; policy analytics activado en la política; falta probar `app1_dns_via_firewall` y añadir alertas.
- Reglas por dominio añadidas el 2026-10-21 (sin desplegar): al desplegar, verificar HTTPS sin SNI, QUIC y los logs `AZFWApplicationRule` (ver `docs/firewall-review.md`). `denied_web_categories` queda vacío hasta que se decida Premium.
- Probar el aislamiento entre spokes: hace falta un segundo spoke (solo hay `app1`).
- Opcional: repetir la prueba desde los primeros minutos tras el despliegue para entender los cuelgues puntuales de la zona 2 (el firewall y la salida funcionaron; no se vio relación con el firewall).
- Probar la entrada por las subnets públicas (appgw/balanceador) y AKS/Container Apps/Function dentro de `app1`.
- `app1` ya aplica el contrato (`app1_*.tf`); el repo `azure-virtual-network` NO se usará ni se modifica.
- (histórico) Aplicar el contrato en `azure-virtual-network` (quitar NAT, route tables de las subnets de entrada, conexión al hub, address space único) y en los consumidores (AKS `outbound_type`).
- CI: workflows plan/apply e identidades. **Los permisos de CI deben vivir en un root persistente separado** (lección de `azure-virtual-network`: al destruir la VNet se perdían los roles de CI).
- Checkov no se ha ejecutado (no está instalado en esta máquina).
- Alertas de SNAT (métricas del NAT Gateway) y de salud del firewall.
- DR en una segunda región (hub + egress propios, el 0/0 no cruza hubs).
