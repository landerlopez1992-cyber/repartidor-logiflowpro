# 🔐 Instrucciones para Configurar el Keystore

## Problema Actual
El AAB se firmó con el keystore de **debug**, pero Google Play requiere el keystore **original** de la app.

- **SHA1 esperado por Google Play:** `17:A5:BF:96:A8:50:A8:1F:EA:51:0E:47:21:9E:C2:D2:F7:10:78:54`
- **SHA1 del AAB actual (debug):** `B3:30:3D:CE:FD:2F:E1:69:E4:FD:4A:FB:AC:BB:F1:DC:CE:97:82:C0`

## Opción 1: Si tienes el keystore original

1. **Encuentra el keystore original** de la app "Logiflow Pro"
   - Busca archivos `.jks` o `.keystore` en tu computadora
   - Puede estar en otro proyecto o en una carpeta de respaldo

2. **Verifica que sea el correcto:**
   ```bash
   keytool -list -v -keystore /ruta/al/keystore.jks
   ```
   - Busca el SHA1 en la salida
   - Debe ser: `17:A5:BF:96:A8:50:A8:1F:EA:51:0E:47:21:9E:C2:D2:F7:10:78:54`

3. **Copia el keystore al proyecto:**
   ```bash
   cp /ruta/al/keystore-original.jks android/app/upload-keystore.jks
   ```

4. **Crea el archivo `android/key.properties`:**
   ```properties
   storeFile=../app/upload-keystore.jks
   storePassword=tu_password_del_keystore
   keyAlias=tu_key_alias
   keyPassword=tu_password_de_la_clave
   ```

5. **Regenera el AAB:**
   ```bash
   flutter clean
   flutter build appbundle --release
   ```

## Opción 2: Si NO tienes el keystore original

### Si es una actualización de la app existente:
- **NO puedes crear un keystore nuevo** - Google Play requiere el mismo keystore
- **Opciones:**
  1. Contacta a Google Play Support para recuperar el keystore
  2. Busca en backups, otros equipos, o documentación del proyecto original

### Si es una app completamente nueva:
- Puedes crear un keystore nuevo, pero **debes publicarla como app nueva** en Google Play
- Esto significa perder el historial, reviews, y usuarios de la app anterior

## Verificar SHA1 de un keystore

```bash
# Si conoces el password
keytool -list -v -keystore /ruta/al/keystore.jks -storepass TU_PASSWORD

# Si no conoces el password, intenta con "android" (solo para debug)
keytool -list -v -keystore /ruta/al/keystore.jks -storepass android
```

## Ubicaciones comunes donde buscar keystores

- `~/Desktop/Proyectos/` (otros proyectos)
- `~/Documents/`
- `~/Downloads/`
- `~/Android/`
- Backups en OneDrive, Google Drive, etc.
- Otros equipos donde se desarrolló la app original

## ¿Dónde está el keystore de la app original "Logiflow Pro"?

Si recuerdas dónde desarrollaste la app original, busca allí. El keystore es **crítico** - sin él no puedes actualizar la app en Google Play.
