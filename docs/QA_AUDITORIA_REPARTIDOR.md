# QA manual — auditoría Repartidor vs VolonexPro+ / tienda

Ejecutar en **staging** (recomendado) o producción solo con acuerdo explícito. Anotar fecha, tenant y usuarios usados.

## Pre-requisitos

- Usuario **repartidor** con `usuarios.tenant_id` definido y nombre conocido (ej. `Juan Pérez`).
- Usuario **master** del mismo tenant.
- Acceso a VolonexPro+ para asignar repartidor y a la tienda/web para crear pedidos.
- App Repartidor instalada en dispositivo real o emulador con misma URL Supabase que staging/prod.

### Verificación rápida en base (solo lectura)

Ajustar `:tenant` y `:nombre`:

```sql
select id, nombre, tenant_id, rol
from usuarios
where tenant_id = :tenant
  and rol ilike '%REPARTIDOR%';
```

Para una orden reciente:

```sql
select id, numero_orden, tenant_id, repartidor_nombre, estado, entrega_por_vendedor
from ordenes
where tenant_id = :tenant
order by fecha_creacion desc
limit 5;
```

---

## 1. Asignación tienda → repartidor + Realtime (`verify-supabase-assign`)

**Objetivo:** confirmar que una orden creada desde tienda/web aparece en la app del repartidor tras asignación con **nombre idéntico** al del usuario.

| Paso | Acción | Resultado esperado |
|------|--------|---------------------|
| 1 | Crear pedido desde tienda/web que genere fila en `ordenes` con `tenant_id` correcto | Orden visible en VolonexPro+ |
| 2 | En VolonexPro+, asignar repartidor cuyo texto sea **exactamente** el `usuarios.nombre` del driver | `repartidor_nombre` en BD = nombre del usuario |
| 3 | En app Repartidor: pull-to-refresh en lista | Orden aparece en la lista del driver |
| 4 | Opcional: repetir sin refrescar; observar si Realtime muestra la orden tras el UPDATE de asignación | Si el INSERT fue sin repartidor, la primera notificación útil suele ser el UPDATE |

**Fallo común:** nombre distinto (espacio extra, mayúsculas solo si la comparación en código es sensible — revisar política actual en `_cargarOrdenes`).

---

## 2. Master ve órdenes sin repartidor (`verify-master-unassigned`)

**Objetivo:** usuario master ve órdenes del tenant **antes** de asignación (filtro por `tenant_id`).

| Paso | Acción | Resultado esperado |
|------|--------|---------------------|
| 1 | Crear orden desde tienda **sin** asignar repartidor en VolonexPro+ | `repartidor_nombre` null o vacío según negocio |
| 2 | Iniciar sesión como **master** en app Repartidor | La orden aparece en la vista master |
| 3 | Iniciar sesión como repartidor normal **distinto** | La orden **no** aparece hasta asignación |

---

## 3. `entrega_por_vendedor` y contactos vendedor (`verify-vendedor-flags`)

**Objetivo:** UI muestra contactos / avisos y no fuerza flujo estándar donde el modelo lo excluye.

| Paso | Acción | Resultado esperado |
|------|--------|---------------------|
| 1 | Orden de prueba con `entrega_por_vendedor = true` y campos `vendedor_contacto_*` poblados | En lista/detalle se muestran datos de contacto vendedor donde aplique |
| 2 | Abrir `detalle_orden_screen` | Revisar que botones/acciones de estado respetan `entregaPorVendedor` (p. ej. ramas que omiten lógica de reparto estándar) |
| 3 | Comparar con orden normal `entrega_por_vendedor = false` | Comportamiento distinto solo donde el código lo condiciona |

Referencia de código: condiciones con `entregaPorVendedor` en `lib/screens/detalle_orden_screen.dart`.

---

## 4. Offline (complemento del plan original)

| Paso | Acción | Resultado esperado |
|------|--------|---------------------|
| 1 | Con órdenes ya cargadas, activar modo avión | App usable con caché donde esté implementado |
| 2 | Volver en línea | `syncPendingOperations` sin errores críticos (revisar logs si falla) |

---

## Cierre

Marcar cada ítem como OK / FAIL y adjuntar capturas o IDs de orden (`ordenes.id`) para trazabilidad.
