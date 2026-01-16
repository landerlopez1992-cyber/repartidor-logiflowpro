# ANÁLISIS COMPLETO DE ERRORES - APP REPARTIDOR LOGIFLOW PRO

## Fecha: 2026-01-15
## Análisis de logs y código

---

## 🚨 ERRORES CRÍTICOS DETECTADOS

### 1. ❌ BUCKET DE FIRMAS NO EXISTE EN SUPABASE STORAGE
**Severidad: CRÍTICA**

**Error en logs:**
```
❌ Error: StorageException(message: Bucket not found, statusCode: 404, error: Bucket not found)
❌ Tipo: upload_firma
❌ Operación descartada después de 3 intentos: upload_firma para orden 974e9f39-4233-42df-a620-71545bcf2210
```

**Causa:**
- El código intenta subir firmas al bucket `'firmas-entrega'` (línea 687 en sync_service.dart)
- Este bucket NO existe en Supabase Storage
- Solo existe el bucket `'fotos-perfil'` para las fotos de entrega

**Ubicación del error:**
- `lib/services/sync_service.dart` - líneas 687-691
- `lib/screens/detalle_orden_screen.dart` - líneas 5911-5916

**Soluciones:**
1. **OPCIÓN A (Recomendada):** Crear el bucket `'firmas-entrega'` en Supabase Storage Dashboard con:
   - Nombre: `firmas-entrega`
   - Público: Sí
   - Políticas de acceso: Permitir lectura pública, escritura autenticada

2. **OPCIÓN B (Alternativa):** Cambiar el código para usar el bucket `'fotos-perfil'` existente

---

### 2. ❌ FIRMA NO APARECE EN UI DE ÓRDENES ENTREGADAS
**Severidad: ALTA**

**Problema:**
La firma se captura, se guarda localmente, se sube a Supabase exitosamente, PERO no se muestra en la UI cuando el repartidor ve una orden entregada.

**Causa:**
La app del repartidor NO tiene ningún widget o sección para mostrar la foto y firma de entrega en órdenes con estado `ENTREGADO`.

**Comparación:**
- **Admin Web** (`ver_orden_screen.dart`): SÍ tiene `_buildSeccionFirma()` (línea 1665) que muestra la firma
- **App Repartidor** (`detalle_orden_screen.dart`): NO tiene ninguna sección para mostrar foto/firma

**Código faltante en detalle_orden_screen.dart:**
Después de `_buildStatusHistoryCard()` (línea 845) debería agregarse:
```dart
// Mostrar foto y firma si la orden está entregada
if (_ordenActual.estado == 'ENTREGADO' || _ordenActual.estado == 'ENTREGADO EN SUCURSAL') ...[
  _buildSeccionEntrega(), // ESTE WIDGET NO EXISTE
  const SizedBox(height: 12),
],
```

---

### 3. ❌ PERMISOS DE UBICACIÓN NO DEFINIDOS EN MANIFEST
**Severidad: CRÍTICA**

**Error en logs (se repite constantemente):**
```
❌ Error iniciando rastreo: No location permissions are defined in the manifest. 
Make sure at least ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION are defined in the manifest.
```

**Causa:**
El archivo `android/app/src/main/AndroidManifest.xml` NO tiene los permisos de ubicación.

**Archivo actual:**
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application...>
    </application>
    <queries>...</queries>
</manifest>
```

**Solución:**
Agregar ANTES de `<application>`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

---

### 4. ⚠️ FOTO LOCAL SE PIERDE EN MODO OFFLINE
**Severidad: ALTA**

**Problema observado en logs:**
```
💾 Foto guardada localmente: /data/user/0/.../cache/scaled_1000189694.png
🔒 Preservando foto local después de recargar: local:///data/user/0/.../cache/scaled_1000189694.png
```

Pero después de cambiar de filtro o recargar, la foto desaparece.

**Causa:**
Las fotos se guardan en la carpeta `cache/` que Android puede limpiar en cualquier momento. Deberían guardarse en almacenamiento persistente.

**Solución:**
Usar `getApplicationDocumentsDirectory()` en lugar de `getTemporaryDirectory()` para fotos pendientes de sincronización.

---

### 5. ⚠️ DETECCIÓN DE CONEXIÓN INCORRECTA
**Severidad: MEDIA-ALTA**

**Problema en logs:**
```
📊 Estado de conexión: Online
🔄 Hay conexión wifi/mobile - Verificando conexión a Supabase antes de sincronizar...
❌ Error verificando conexión a Supabase: ClientException with SocketException: 
Failed host lookup: 'fbbvfzeyhhopdwzsooew.supabase.co'
```

**Causa:**
La app detecta que hay WiFi/datos móviles activos, pero NO verifica si realmente puede alcanzar Supabase. Luego intenta sincronizar y falla.

**Comportamiento actual:**
1. `connectivity_plus` dice "Online" ✅
2. App intenta sincronizar inmediatamente
3. Falla porque no puede resolver DNS de Supabase ❌
4. Entra en ciclo de reintentos innecesarios

**Solución:**
La app ya tiene la función `_verificarConexionSupabase()`, pero necesita:
- Mejor manejo de errores de DNS
- No mostrar "Online" si no puede alcanzar Supabase
- Evitar intentos de sincronización si la verificación falla

---

### 6. ⚠️ ORDEN #2086 EXCLUIDA INCORRECTAMENTE
**Severidad: MEDIA**

**Log problemático:**
```
⚠️ [FILTRO MASTER] Orden #2086 con recoger_en_sucursal = true 
pero interruptor DESACTIVO - Excluyendo (NADIE la ve)
```

Luego más tarde:
```
✅ Configuración de recogida en sucursal cargada: solo_master=true
```

**Problema:**
La orden se excluye ANTES de cargar la configuración `solo_master`. Esto causa que la orden desaparezca temporalmente de la lista.

**Causa:**
Race condition: El filtro se aplica antes de que termine de cargarse la configuración desde Supabase.

---

### 7. ⚠️ ERRORES SUPABASE EN MODO OFFLINE (RUIDO)
**Severidad: BAJA (pero molesta)**

**Logs repetidos constantemente:**
```
❌ Error verificando datos del repartidor en BD: ClientException...
📴 Sin conexión - Error cargando sucursal ignorado (modo offline)...
❌ Error al cargar mensajes no leídos: ClientException...
❌ Error cargando notificaciones no leídas: ClientException...
🔔 Estado de suscripción Realtime: RealtimeSubscribeStatus.channelError
```

**Causa:**
Muchas operaciones intentan conectarse a Supabase incluso en modo offline, generando logs de error innecesarios.

**Solución:**
Verificar `isOnline` ANTES de intentar operaciones no críticas (sucursal, notificaciones, realtime).

---

### 8. ⚠️ ORDEN #2152 NO ENCONTRADA (BÚSQUEDA FALLIDA)
**Severidad: INFORMATIVA**

**Log:**
```
⚠️ [DIAGNÓSTICO] Orden #2152 NO encontrada en la respuesta de la BD
   - Órdenes que contienen "215": []
   - Primeras 10 órdenes en respuesta: [2121, 2142, 2082, 2046, 2086, 2083, 2023, 2115]
```

**Causa:**
El código busca una orden #2152 que no existe en la base de datos. Probablemente fue eliminada o nunca existió.

---

## 📋 PROBLEMAS SECUNDARIOS

### 9. Sincronización duplicada
Los logs muestran múltiples llamadas a sincronización simultáneas:
```
🔄 Sincronizando 4 operaciónes pendientes...
🔄 Sincronizando 4 operaciónes pendientes... (duplicado)
⚠️ Ya hay una sincronización en progreso
```

### 10. Verificación periódica de notificaciones en offline
```
🔄 Verificando notificaciones no leídas periódicamente...
📴 Sin conexión - Verificación periódica omitida (modo offline)
```
Se ejecuta cada 5 segundos incluso sin conexión.

---

## 🔧 PLAN DE CORRECCIÓN PRIORITARIO

### PRIORIDAD 1 - ERRORES CRÍTICOS QUE BLOQUEAN FUNCIONALIDAD

1. **Agregar permisos de ubicación GPS** (2 minutos)
   - Editar `android/app/src/main/AndroidManifest.xml`
   - Agregar permisos ACCESS_FINE_LOCATION y ACCESS_COARSE_LOCATION

2. **Crear bucket 'firmas-entrega' en Supabase** (1 minuto)
   - Acceder al dashboard de Supabase Storage
   - Crear bucket público llamado `firmas-entrega`
   - Configurar políticas de acceso

### PRIORIDAD 2 - ERRORES QUE AFECTAN UX

3. **Agregar visualización de firma en UI** (30 minutos)
   - Crear `_buildSeccionEntrega()` en detalle_orden_screen.dart
   - Mostrar foto Y firma cuando estado = ENTREGADO
   - Inspirarse en el código del admin (ver_orden_screen.dart líneas 1665-1895)

4. **Corregir persistencia de fotos offline** (15 minutos)
   - Cambiar carpeta de `cache/` a `documents/fotos_entrega/`
   - Asegurar que las fotos no se borren automáticamente

5. **Mejorar detección de conexión** (20 minutos)
   - No marcar como "Online" si DNS falla
   - Evitar ciclos de reintentos innecesarios
   - Mejorar feedback al usuario

### PRIORIDAD 3 - OPTIMIZACIONES

6. **Corregir race condition de filtro orden #2086** (10 minutos)
7. **Reducir ruido de logs en modo offline** (10 minutos)
8. **Prevenir sincronizaciones duplicadas** (5 minutos)

---

## 📊 RESUMEN EJECUTIVO

### Errores encontrados: 8
- **Críticos (bloquean funcionalidad):** 3
  - Bucket de firmas no existe
  - Permisos GPS faltantes
  - Firma no se visualiza

- **Altos (afectan UX):** 2
  - Foto se pierde en modo offline
  - Detección de conexión incorrecta

- **Medios:** 2
  - Orden #2086 filtrada incorrectamente
  - Sincronizaciones duplicadas

- **Informativos:** 1
  - Orden #2152 no encontrada (dato incorrecto)

### Tiempo estimado de corrección: 1.5 horas

---

## 🔍 HALLAZGOS ADICIONALES

### Diferencias entre Admin Web y App Repartidor

**Admin Web tiene pero Repartidor NO:**
- ✅ Sección de visualización de firma (`_buildSeccionFirma`)
- ✅ Imagen de firma renderizada en UI
- ✅ Estados de "Firma obtenida" vs "Firma pendiente"

**Ambos tienen:**
- ✅ Campo `firmaUrl` en modelo Orden
- ✅ Campo `requiereFirma` en modelo Orden
- ✅ Lógica de captura de firma (SignatureController)
- ✅ Subida de firma a Storage (aunque con bucket incorrecto)

### Flujo de firma actual (con problemas):
1. ✅ Repartidor captura firma
2. ✅ Se guarda localmente
3. ❌ Se intenta subir a bucket inexistente → FALLA
4. ✅ Se encola para reintento
5. ❌ Se descarta después de 3 reintentos
6. ✅ La orden se marca como ENTREGADO (sin firma_url)
7. ❌ El repartidor no puede ver la firma capturada

### Flujo correcto esperado:
1. ✅ Repartidor captura firma
2. ✅ Se guarda en almacenamiento persistente (NO cache)
3. ✅ Se sube a bucket 'firmas-entrega' correctamente
4. ✅ Se actualiza firma_url en tabla ordenes
5. ✅ Se muestra en UI del repartidor (FALTANTE ACTUALMENTE)
6. ✅ Se muestra en admin web

---

## 📁 ARCHIVOS QUE NECESITAN MODIFICACIÓN

### Archivos a modificar:
1. `android/app/src/main/AndroidManifest.xml` - Agregar permisos GPS
2. `lib/screens/detalle_orden_screen.dart` - Agregar visualización de firma/foto
3. `lib/screens/detalle_orden_screen.dart` - Cambiar carpeta de fotos (cache → documents)
4. `lib/services/sync_service.dart` - Mejorar manejo de errores
5. `lib/screens/repartidor_mobile_screen.dart` - Corregir race condition filtro

### Archivos de referencia (admin web):
- `/Proyectos/julio pauqteria sotfware/paqueteria_app/lib/screens/ver_orden_screen.dart` (líneas 1665-1895)
  - Tiene implementación completa de visualización de firma

---

## 🗄️ CAMBIOS NECESARIOS EN SUPABASE

### Storage Buckets:
- ✅ Existente: `fotos-perfil` (funciona correctamente)
- ❌ Faltante: `firmas-entrega` (DEBE CREARSE)

### Tabla ordenes (campos de firma):
- ✅ `requiere_firma` BOOLEAN - Existe
- ✅ `firma_url` TEXT - Existe
- ✅ Campo presente en ambos proyectos (admin y repartidor)

---

## 🔄 FLUJO DE SINCRONIZACIÓN OFFLINE (ANÁLISIS)

### Funcionamiento actual:
1. **Modo Online:**
   - Foto sube → ✅ Funciona
   - Firma sube → ❌ Falla (bucket no existe)
   - Estado actualiza → ✅ Funciona

2. **Modo Offline:**
   - Foto guarda en cache local → ⚠️ Se puede perder
   - Firma guarda en files/firmas_entrega → ✅ Mejor ubicación
   - Ambas se encolan para sincronización → ✅ Funciona
   - Al recuperar conexión, sincroniza → ⚠️ Firma falla por bucket

3. **Orden #2142 (entregada en modo offline):**
   ```
   📸 DEBUG - Foto: https://fbbvfzeyhhopdwzsooew.supabase.co/.../entrega_4159...jpg
   ✍️ DEBUG - Firma: null
   ```
   La foto se había subido antes, pero la firma nunca llegó.

4. **Orden #2086 (entregada con foto y firma en offline):**
   ```
   📸 DEBUG - Foto: local:///data/.../cache/scaled_1000189694.png
   ✍️ DEBUG - Firma: local:///data/.../files/firmas_entrega/firma_974...png
   ```
   Ambas pendientes de subir, pero firma fallará por bucket inexistente.

---

## 🐛 BUGS DE LÓGICA DE NEGOCIO

### Bug #1: Estado inconsistente orden-cache después de hot reload
**Logs:**
```
💾 ✅ 8 órdenes cargadas desde caché
   - Orden #2142: estado=EN REPARTO
```
Pero la orden ya fue marcada como ENTREGADO. El caché no se invalidó correctamente.

### Bug #2: Foto duplicada en pending_photos
**Logs:**
```
♻️ Operación existente actualizada (dedupe): upload_photo - Orden: 974e9f39...
```
Se agrega la misma foto múltiples veces, el sistema de deduplicación la detecta.

### Bug #3: Firma guardada pero no actualizada en marca de entrega
**Secuencia:**
1. `💾 Firma guardada localmente`
2. `✍️ DEBUG - Firma que se enviará: local://...`
3. `📝 Datos a actualizar: {estado: ENTREGADO, fecha_entrega: ...}` ← NO incluye firma_url

El campo `firma_url` NO se está incluyendo en el update cuando se marca como entregado.

---

## 🎯 CORRECCIONES ESPECÍFICAS POR ARCHIVO

### `lib/screens/detalle_orden_screen.dart`

#### Línea ~1640 - Método `_marcarComoEntregado()`:
**Problema:** No incluye `firma_url` en el update
```dart
updateData['foto_entrega'] = _fotoEntregaUrl; // ✅ Foto se incluye
// ❌ FALTA: updateData['firma_url'] = _firmaUrl;
```

**Corrección:**
```dart
if (_firmaUrl != null && _firmaUrl!.isNotEmpty) {
  updateData['firma_url'] = _firmaUrl;
}
```

#### Línea ~850 - Método `build()`:
**Problema:** No muestra foto/firma en entregadas
```dart
_buildStatusHistoryCard(),
// ❌ FALTA: Sección de entrega con foto y firma
```

**Corrección:** Agregar después de `_buildStatusHistoryCard()`:
```dart
// Mostrar evidencia de entrega si está entregada
if (_ordenActual.estado == 'ENTREGADO' || 
    _ordenActual.estado == 'ENTREGADO EN SUCURSAL') ...[
  _buildSeccionEntrega(),
  const SizedBox(height: 12),
],
```

#### Nuevo método a crear: `_buildSeccionEntrega()`
Debe mostrar:
- Foto de entrega (si existe)
- Firma del cliente (si existe)
- Fecha y hora de entrega
- Repartidor que entregó

---

### `android/app/src/main/AndroidManifest.xml`

**Línea 1 - Agregar después de `<manifest>`:**
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- AGREGAR ESTOS PERMISOS -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    
    <application...>
```

---

### `lib/services/sync_service.dart`

#### Línea 687 - Nombre del bucket:
**Opción A (después de crear bucket):**
```dart
await supabase.storage
    .from('firmas-entrega') // ✅ Bucket correcto (crear primero)
    .uploadBinary(fileName, firmaBytes);
```

**Opción B (usar bucket existente):**
```dart
await supabase.storage
    .from('fotos-perfil') // ✅ Bucket que ya existe
    .uploadBinary(fileName, firmaBytes);
```

---

## 📸 COMPARACIÓN: ADMIN WEB vs APP REPARTIDOR

### Admin Web (`ver_orden_screen.dart`):
```dart
Widget _buildSeccionFirma() {
  final tieneFirma = _orden.firmaUrl != null && _orden.firmaUrl!.isNotEmpty;
  
  return Card(
    child: Column(
      children: [
        // Título con ícono
        Row(
          children: [
            Icon(tieneFirma ? Icons.check_circle : Icons.pending),
            Text(tieneFirma ? 'Firma obtenida' : 'Firma pendiente'),
          ],
        ),
        // Imagen de la firma
        if (tieneFirma)
          Image.network(_orden.firmaUrl!),
      ],
    ),
  );
}
```

### App Repartidor (`detalle_orden_screen.dart`):
```dart
// ❌ NO EXISTE - DEBE CREARSE
```

---

## ✅ VALIDACIONES EXITOSAS (LO QUE SÍ FUNCIONA)

1. ✅ Sistema de caché offline funciona correctamente
2. ✅ Cola de sincronización funciona (excepto firmas por bucket)
3. ✅ Fotos se suben correctamente al bucket 'fotos-perfil'
4. ✅ Detección de modo offline funciona
5. ✅ Preservación de estado local en modo offline
6. ✅ Sistema de reintentos automáticos funciona
7. ✅ Deduplicación de operaciones funciona
8. ✅ Captura de firma funciona (UI de SignaturePad)

---

## 🎬 PRÓXIMOS PASOS RECOMENDADOS

1. Crear bucket 'firmas-entrega' en Supabase
2. Agregar permisos GPS al AndroidManifest.xml
3. Agregar `_buildSeccionEntrega()` para mostrar foto/firma en UI
4. Incluir `firma_url` en el update de `_marcarComoEntregado()`
5. Cambiar almacenamiento de fotos de cache a documents
6. Mejorar detección de conexión a Supabase
7. Corregir race condition en filtro de órdenes
8. Reducir logs innecesarios en modo offline

---

## 📝 NOTAS TÉCNICAS

### Carpetas de almacenamiento en Android:
- **Cache:** `/data/user/0/.../cache/` - SE PUEDE BORRAR EN CUALQUIER MOMENTO
- **Files:** `/data/user/0/.../files/` - Persistente, protegida
- **Documents:** Vía `getApplicationDocumentsDirectory()` - RECOMENDADA

### Rutas de archivos en logs:
- ✅ Firma: `files/firmas_entrega/firma_974...png` - Buena ubicación
- ⚠️ Foto: `cache/scaled_1000189694.png` - Ubicación temporal

### URLs de archivos:
- Remote (subido): `https://fbbvfzeyhhopdwzsooew.supabase.co/storage/v1/...`
- Local (pendiente): `local:///data/user/0/.../files/...`

---

*Fin del análisis - Documento generado automáticamente*
