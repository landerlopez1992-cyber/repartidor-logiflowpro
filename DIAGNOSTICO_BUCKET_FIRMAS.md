# 🔥 DIAGNÓSTICO: INCONSISTENCIA DE BUCKETS DE FIRMAS

## PROBLEMA CRÍTICO ENCONTRADO

### ❌ LOS DOS PROYECTOS USAN NOMBRES DIFERENTES DE BUCKET

---

## 📊 COMPARACIÓN ENTRE PROYECTOS

### PROYECTO ADMIN WEB (julio paqueteria software/paqueteria_app)

**Archivo:** `lib/screens/detalle_orden_screen.dart` (línea 5112)
```dart
await supabase.storage.from('firmas').uploadBinary(  // ← USA 'firmas'
  fileName,
  firmaBytes,
);
```

**Archivo:** `lib/services/sync_service.dart` (línea 256)
```dart
await supabase.storage
    .from('firmas-entrega')  // ← USA 'firmas-entrega'
    .uploadBinary(fileName, firmaBytes);
```

**⚠️ EL PROYECTO ADMIN TIENE INCONSISTENCIA INTERNA!**
- Usa `'firmas'` en un lugar
- Usa `'firmas-entrega'` en otro lugar

---

### PROYECTO APP REPARTIDOR (Repartidor Logiflow Pro)

**Archivo:** `lib/services/sync_service.dart` (línea 687)
```dart
await supabase.storage
    .from('firmas-entrega')  // ← USA 'firmas-entrega'
    .uploadBinary(fileName, firmaBytes);
```

**Archivo:** `lib/screens/detalle_orden_screen.dart` (línea 5911)
```dart
await supabase.storage.from('firmas-entrega').uploadBinary(  // ← USA 'firmas-entrega'
  fileName,
  firmaBytes,
);
```

**✅ APP REPARTIDOR ES CONSISTENTE INTERNAMENTE**
- Siempre usa `'firmas-entrega'`

---

## 🎯 EL VERDADERO PROBLEMA

### Error en logs de la app repartidor:
```
❌ StorageException(message: Bucket not found, statusCode: 404, error: Bucket not found)
❌ Tipo: upload_firma
```

**SIGNIFICA QUE EN SUPABASE:**
- ❌ NO existe bucket `'firmas-entrega'`
- ❓ ¿Existe bucket `'firmas'`?
- ✅ SÍ existe bucket `'fotos-perfil'` (las fotos funcionan)

---

## 🔍 ¿QUÉ BUCKET EXISTE REALMENTE EN SUPABASE?

### Necesitas verificar en el Dashboard de Supabase:
1. Ir a **Storage** → **Buckets**
2. Buscar:
   - ¿Existe `fotos-perfil`? → ✅ SÍ (confirmado por logs)
   - ¿Existe `firmas`? → ❓ DESCONOCIDO
   - ¿Existe `firmas-entrega`? → ❌ NO (confirmado por error 404)

---

## ✅ SOLUCIONES POSIBLES

### OPCIÓN 1: Crear bucket 'firmas-entrega' (RECOMENDADA)
**Pros:**
- Mantiene la separación de fotos y firmas
- No hay que cambiar código en la app repartidor
- Solo hay que actualizar el admin web para usar 'firmas-entrega' consistentemente

**Pasos:**
1. Crear bucket `'firmas-entrega'` en Supabase Storage
2. Configurar como público
3. Corregir el admin web (línea 5112) para usar `'firmas-entrega'` en lugar de `'firmas'`

### OPCIÓN 2: Usar bucket 'fotos-perfil' para todo
**Pros:**
- No hay que crear nuevo bucket
- Un solo bucket para fotos y firmas

**Contras:**
- Menos organización
- Hay que cambiar código en ambos proyectos

### OPCIÓN 3: Usar bucket 'firmas' si ya existe
**Pros:**
- Si ya existe, no crear otro
- Solo cambiar app repartidor

**Contras:**
- Hay que verificar primero si existe
- Cambiar código en la app repartidor

---

## 📝 RECOMENDACIÓN

### 1. PRIMERO: Verificar qué buckets existen
Accede a tu Supabase Dashboard → Storage y lista todos los buckets.

### 2. SEGUNDO: Elegir estrategia según lo que existe

**Si existe 'firmas':**
- Cambiar app repartidor para usar `'firmas'`
- Cambiar admin web sync_service.dart para usar `'firmas'`

**Si NO existe ningún bucket de firmas:**
- Crear `'firmas-entrega'` (nombre más descriptivo)
- Cambiar admin web detalle_orden_screen.dart para usar `'firmas-entrega'`

**Si quieres simplificar:**
- Usar `'fotos-perfil'` para ambos (fotos y firmas)
- Cambiar ambos proyectos

---

## 🔧 CAMBIOS ESPECÍFICOS NECESARIOS

### Si decides usar 'firmas-entrega' (RECOMENDADO):

#### Proyecto Admin Web:
**Archivo:** `lib/screens/detalle_orden_screen.dart`
**Línea:** 5112
**Cambiar:**
```dart
await supabase.storage.from('firmas').uploadBinary(  // ❌ INCORRECTO
```
**Por:**
```dart
await supabase.storage.from('firmas-entrega').uploadBinary(  // ✅ CORRECTO
```

**Línea:** 5117
**Cambiar:**
```dart
final urlResponse = supabase.storage.from('firmas').getPublicUrl(fileName);  // ❌
```
**Por:**
```dart
final urlResponse = supabase.storage.from('firmas-entrega').getPublicUrl(fileName);  // ✅
```

#### Proyecto App Repartidor:
**✅ NO NECESITA CAMBIOS** - Ya usa 'firmas-entrega' consistentemente

---

## 🎬 PRÓXIMO PASO INMEDIATO

**ACCIÓN REQUERIDA:**
Por favor verifica en tu Dashboard de Supabase (Project → Storage → Buckets) qué buckets existen actualmente:

```
Buckets existentes:
[ ] fotos-perfil
[ ] firmas
[ ] firmas-entrega
[ ] avatars
[ ] Otros: __________
```

Una vez que sepamos qué buckets existen, te diré exactamente qué código cambiar en cada proyecto.

---

*Documento generado: 2026-01-15*
