# Implementación Offline-First - App Repartidor

## ✅ Características Implementadas

### 1. **Almacenamiento Local Completo**
- ✅ Órdenes en caché local (**SharedPreferences** + merge con cola de sync)
- ✅ Fotos/firmas en **SQLite** (`offline_data.db`)
- ✅ GPS, notificaciones, chat y mapa con caché (`repartidor_pantallas_offline_service.dart`)
- ✅ Fotos de entrega se guardan en archivos locales
- ✅ Firmas se guardan en archivos locales
- ✅ Todos los cambios de estado se guardan localmente primero

### 2. **Sincronización Automática**
- ✅ El sistema detecta cuando hay conexión a internet
- ✅ Sincroniza automáticamente todas las operaciones pendientes
- ✅ Sincroniza fotos y firmas desde archivos locales
- ✅ Reintentos automáticos en caso de fallos

### 3. **Manejo de Errores**
- ✅ Servicio de manejo de errores con modales informativos
- ✅ Muestra errores claros al usuario
- ✅ No interrumpe el flujo de trabajo offline

## 📋 Cómo Funciona

### Patrón Offline-First

**Todas las operaciones siguen este patrón:**

1. **Guardar localmente primero** (siempre funciona, incluso sin internet)
2. **Intentar sincronizar si hay conexión** (en segundo plano)
3. **Si no hay conexión**, agregar a cola de sincronización
4. **Sincronizar automáticamente** cuando regrese la conexión

### Ejemplo: Cambiar Estado de Orden

```dart
// 1. Actualizar estado localmente (siempre funciona)
orden.estado = 'ENTREGADO';
await OrdenCacheService.updateCachedOrder(orden);

// 2. Intentar sincronizar si hay conexión
final syncService = SyncService();
if (syncService.isOnline) {
  try {
    await supabase.from('ordenes').update({'estado': 'ENTREGADO'}).eq('id', orden.id);
    print('✅ Sincronizado exitosamente');
  } catch (e) {
    // Si falla, agregar a cola de sincronización
    await syncService.addOperation(
      type: 'update_orden_estado',
      ordenId: orden.id,
      data: {'estado': 'ENTREGADO'},
    );
  }
} else {
  // Sin conexión, agregar a cola directamente
  await syncService.addOperation(
    type: 'update_orden_estado',
    ordenId: orden.id,
    data: {'estado': 'ENTREGADO'},
  );
}
```

### Ejemplo: Tomar Foto de Entrega

```dart
// 1. Guardar foto localmente (siempre funciona)
await OfflineStorageService().savePendingPhoto(
  ordenId: orden.id,
  filePath: image.path,
);

// 2. Intentar subir si hay conexión
final syncService = SyncService();
if (syncService.isOnline) {
  try {
    // Subir a Supabase Storage
    await supabase.storage.from('fotos-perfil').uploadBinary(fileName, fileBytes);
    // Actualizar orden con URL de la foto
    await supabase.from('ordenes').update({'foto_entrega': imageUrl}).eq('id', orden.id);
  } catch (e) {
    // Si falla, agregar a cola de sincronización
    await syncService.addOperation(
      type: 'upload_photo',
      ordenId: orden.id,
      data: {
        'file_path': image.path,
        'photo_base64': base64Encode(fileBytes),
      },
    );
  }
} else {
  // Sin conexión, agregar a cola directamente
  await syncService.addOperation(
    type: 'upload_photo',
    ordenId: orden.id,
    data: {
      'file_path': image.path,
      'photo_base64': base64Encode(fileBytes),
    },
  );
}
```

## 🔧 Servicios Disponibles

### OfflineStorageService
```dart
// Guardar operación pendiente
await OfflineStorageService().savePendingOperation(
  type: 'update_orden_estado',
  ordenId: orden.id,
  data: {'estado': 'ENTREGADO'},
);

// Guardar foto pendiente
await OfflineStorageService().savePendingPhoto(
  ordenId: orden.id,
  filePath: image.path,
);

// Guardar firma pendiente
await OfflineStorageService().savePendingSignature(
  ordenId: orden.id,
  filePath: signature.path,
);

// Guardar orden en caché
await OfflineStorageService().cacheOrder(orden.id, ordenJson);

// Obtener orden desde caché
final ordenCached = await OfflineStorageService().getCachedOrder(orden.id);
```

### SyncService
```dart
// Verificar si hay conexión
final syncService = SyncService();
if (syncService.isOnline) {
  // Hacer operación online
} else {
  // Agregar a cola de sincronización
}

// Agregar operación a cola
await syncService.addOperation(
  type: 'update_orden_estado',
  ordenId: orden.id,
  data: {'estado': 'ENTREGADO'},
);

// Sincronizar manualmente (se hace automáticamente cuando hay conexión)
await syncService.syncPendingOperations();

// Verificar operaciones pendientes
if (syncService.hasPendingOperations) {
  print('Hay ${syncService.pendingOperationsCount} operaciones pendientes');
}
```

### ErrorHandlerService
```dart
// Mostrar error
await ErrorHandlerService.handleError(
  context,
  error,
  titulo: 'Error al guardar',
  mensajePersonalizado: 'No se pudo guardar la orden. Los datos se guardaron localmente.',
);

// Mostrar error con detalle técnico
await ErrorHandlerService.showErrorModal(
  context,
  'Error',
  'Mensaje de error',
  detalleTecnico: error.toString(),
);

// Mostrar advertencia
await ErrorHandlerService.showWarningModal(
  context,
  'Advertencia',
  'Mensaje de advertencia',
);

// Mostrar éxito
await ErrorHandlerService.showSuccessModal(
  context,
  'Éxito',
  'Operación completada exitosamente',
);
```

## 📝 Estado offline (actualizado)

### Funciones con patrón offline-first:
- ✅ Cambios de estado vía `OrdenEstadoSyncHelper` (lista, detalle, QR, ruta)
- ✅ Fotos y firmas + cola `SyncService`
- ✅ GPS en cola (`ubicacion_offline_service.dart`)
- ✅ Chat soporte: lectura en caché + envío en cola
- ✅ Notificaciones: caché + timeout de red
- ✅ Mapa repartidor: última ubicación en caché
- ✅ Iniciar recolecta colaborador: cola `rpc_iniciar_recolecta`
- ✅ Notificaciones email/WhatsApp: trigger BD (no duplicar desde app)

### Limitaciones conocidas:
- ⚠️ **Primer login** requiere internet
- ⚠️ **Ruta optimizada / tiles del mapa** requieren red para datos nuevos
- ⚠️ Marcar notificación como leída offline: se aplica al reconectar (sin cola dedicada aún)

## ⚠️ Notas Importantes

- **La app funciona completamente offline** - todas las operaciones se guardan localmente
- **La sincronización es automática** - cuando hay conexión, todo se sincroniza en segundo plano
- **No se pierden datos** - si falla la sincronización, los datos quedan en la cola local
- **Manejo de errores robusto** - todos los errores se muestran al usuario de forma clara
