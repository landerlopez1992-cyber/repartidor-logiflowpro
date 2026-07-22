# Actualización obligatoria — App Repartidor (Google Play manual)

La app compara la versión instalada (`PackageInfo`) con la publicada en Google Play
(y la API `in_app_update`). El modal **no se quita** al abrir la tienda: solo cuando
la versión instalada ya es suficiente y el usuario vuelve a la app.

El AAB se sube **a mano** a Play Console (no hay upload automático en este repo).

## Checklist operativo (producción Android)

1. **Bump de versión** en `pubspec.yaml` del repo Repartidor  
   Ejemplo: `1.0.22+31` → `1.0.23+32` (`versionName+versionCode`).

2. **Compilar AAB**
   ```bash
   cd "Repartidor Logiflow Pro"
   flutter build appbundle --release
   ```
   Artefacto: `build/app/outputs/bundle/release/app-release.aab`

3. **Subir a Play Console** (producción o la pista que usen los repartidores).

4. **Esperar a que la versión esté live** (visible / instalable en esa pista).

5. **URL de tienda** (Super Admin → App tienda / descargas):  
   `https://play.google.com/store/apps/details?id=com.logiflowpro.repartidor`  
   Guardar en `google_play_store_url` si aún no está.

6. **(Opcional)** Super Admin → **Enviar actualización forzada** Android  
   Solo **después** del paso 4. Sirve de refuerzo (onda + push); la detección
   automática por tienda también bloquea sin este paso.

7. **Verificar**
   - App antigua instalada → al abrir / al volver del background: modal bloqueante.
   - Abrir Play **sin** instalar → al volver, el modal **sigue**.
   - Instalar la versión nueva → al volver, el modal **desaparece**.

## iOS

Misma lógica cuando exista listing en App Store (`apple_store_listing_url` con `/id…`).
Sin URL válida de App Store, la app **no** bloquea en iOS.
