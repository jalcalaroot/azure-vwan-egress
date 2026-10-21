# Revisión del uso del Azure Firewall (2026-10-21)

Se comparó la configuración con las recomendaciones oficiales de Microsoft: [Architecture best practices for Azure Firewall](https://learn.microsoft.com/azure/well-architected/service-guides/azure-firewall), [Secure your Azure Firewall deployment](https://learn.microsoft.com/azure/firewall/secure-firewall), [Best practices for Azure Firewall performance](https://learn.microsoft.com/azure/firewall/firewall-best-practices), [Threat intelligence](https://learn.microsoft.com/azure/firewall/threat-intel) y [DNS settings](https://learn.microsoft.com/azure/firewall/dns-settings).

## Conclusión

No faltan reglas "predeterminadas": Azure no ofrece un paquete de reglas listo para aplicar. Lo que Microsoft mantiene (inteligencia de amenazas, FQDN tags, service tags, web categories, IDPS en Premium) se usa dentro de reglas propias. Con la salida abierta **a propósito**, el firewall hoy actúa como punto de SNAT, de inteligencia de amenazas y de registro; no filtra por dominio ni por categoría. Es una decisión de diseño, no un fallo, pero conviene saberlo.

## Estado frente a las recomendaciones

| Recomendación de Microsoft | Estado |
|---|---|
| Zonas de disponibilidad (zona-redundante) | Cumplido (3 zonas) |
| Política (Firewall Policy) gestionada como código | Cumplido |
| Subnet dedicada `AzureFirewallSubnet` /26 | Cumplido |
| Logs de diagnóstico estructurados (tablas `AZFW*`, destino `Dedicated`) en Log Analytics | Cumplido; se usaron para la evidencia |
| NAT Gateway para evitar el agotamiento de puertos SNAT (64.512 por IP frente a 2.496) | Cumplido |
| No usar el firewall para tráfico dentro de una VNet (usar NSG) | Cumplido (NSG por subnet) |
| Inteligencia de amenazas en alerta y bloqueo | **Corregido** (antes `Alert`, ahora `Deny`). En modo `Alert`, una regla de red con destino 80/443 enmascara las alertas ([problema conocido](https://learn.microsoft.com/troubleshoot/azure/firewall/firewall-known-issues)) |
| DNS proxy | **Activado en la política**. Para que surta efecto la VNet debe usar la IP del firewall como DNS (`app1_dns_via_firewall`, por defecto `false`; ver abajo) |
| Alertas de rendimiento y salud (throughput, health state, SNAT port utilization, latency probe) y de aciertos de inteligencia de amenazas | **Falta** |
| Policy analytics | **Falta** (bloque `insights` de la política) |
| Reglas de aplicación (FQDN/SNI), FQDN tags, web categories | No se usan: la salida está abierta por decisión del propietario |
| IDPS, TLS inspection, filtrado por URL | No disponible en Standard; requiere Premium (precio sin consultar) |
| Mantenimiento controlado por el cliente | No configurado (menor) |

## DNS proxy: cómo completarlo

Microsoft exige tres pasos: activar el proxy (hecho), elegir los servidores DNS (por defecto Azure DNS) y **apuntar el DNS de la VNet a la IP privada del firewall**. Mientras `app1_dns_via_firewall = false`, el paso 3 no está hecho y el proxy no recibe consultas.

Riesgo conocido antes de activarlo: el firewall reenvía a Azure DNS **desde `vnet-egress`**, así que las zonas de Private DNS (`privatelink.*`) deben vincularse también a `vnet-egress`, o usarse Azure DNS Private Resolver (patrón de Microsoft para [Private Link y DNS en Virtual WAN](https://learn.microsoft.com/azure/architecture/networking/guide/private-link-virtual-wan-dns-single-region-workload)). En este repo no hay private endpoints ni zonas, por lo que no se probó; en una VNet con endpoints privados, activarlo sin eso rompería su resolución.

## Comportamientos a tener presentes

- Tiempo de inactividad TCP hacia internet: 4 minutos por defecto (ampliable a 15 con soporte). Conexiones largas e inactivas se cortan con RST.
- Si el firewall se desasigna y reasigna puede cambiar su IP privada, y la ruta estática del hub apunta a ella.
- La inteligencia de amenazas se evalúa antes que las reglas de NAT, red y aplicación.

## Siguientes pasos posibles (ninguno aplicado)

1. Probar `app1_dns_via_firewall = true` en el próximo despliegue (verificar DNS desde las VMs y en los logs `AZFWDnsQuery`).
2. Alertas de salud, SNAT y aciertos de inteligencia de amenazas (hace falta un action group).
3. Activar policy analytics.
4. Si en algún momento se quiere filtrar sin cerrar la salida: negar solo categorías de alto riesgo con web categories, o evaluar Premium para IDPS.
