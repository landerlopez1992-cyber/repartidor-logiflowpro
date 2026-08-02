import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Pantalla de ayuda completa para repartidores
/// Muestra guía detallada sobre todos los procesos de la app
class RepartidorAyudaScreen extends StatefulWidget {
  const RepartidorAyudaScreen({super.key});

  @override
  State<RepartidorAyudaScreen> createState() => _RepartidorAyudaScreenState();
}

class _RepartidorAyudaScreenState extends State<RepartidorAyudaScreen> {
  // Controlar qué secciones están expandidas
  final Map<int, bool> _seccionesExpandidas = {
    0: false, // Índice de Contenido
    1: false, // Proceso de Envío y Recepción
    2: false, // Proceso de Entrega
    3: false, // Gestión de Órdenes
    4: false, // Conexión a Internet
    5: false, // Solicitud de Pagos
    6: false, // Perfil y Configuración
    7: false, // Localización GPS
    8: false, // Ruta Optimizada
    9: false, // Chat con la Empresa
    10: false, // Master, Recolector y Remesas
    11: false, // Viajes (Taxi)
    12: false, // Compras de tienda y actualizaciones
  };
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text(
          'Guía de Ayuda',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner de bienvenida
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.exito.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.help_outline,
                    size: 48,
                    color: AppColors.exito,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bienvenido a la Guía de Ayuda',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aquí encontrarás cómo usar entregas, ruta optimizada, modo sin internet, '
                    'Viajes (taxi), chat y liquidaciones de forma clara y actualizada.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.darkTextMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Índice de secciones
            _buildSeccionExpandible(
              indice: 0,
              titulo: 'Índice de Contenido',
              icono: Icons.list,
              contenido: [
                _buildItemLista('1. Proceso de Envío y Recepción'),
                _buildItemLista('2. Proceso de Entrega'),
                _buildItemLista('3. Gestión de Órdenes'),
                _buildItemLista('4. Conexión a Internet'),
                _buildItemLista('5. Solicitud de Pagos'),
                _buildItemLista('6. Perfil y Configuración'),
                _buildItemLista('7. Localización GPS'),
                _buildItemLista('8. Ruta Optimizada'),
                _buildItemLista('9. Chat con la Empresa'),
                _buildItemLista('10. Master, Recolector y Remesas'),
                _buildItemLista('11. Viajes (Taxi)'),
                _buildItemLista('12. Compras de tienda y actualizaciones'),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 1: Proceso de Envío y Recepción
            _buildSeccionExpandible(
              indice: 1,
              titulo: '1. Proceso de Envío y Recepción',
              icono: Icons.local_shipping,
              contenido: [
                _buildSubTitulo('¿Cómo se envían las órdenes?'),
                _buildTexto(
                  'Las órdenes son creadas por la empresa en la plataforma web. Una vez creadas, '
                  'pasan por diferentes estados hasta llegar a ti como repartidor.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Estados de las Órdenes (envío a domicilio):'),
                _buildItemLista('• POR ENVIAR: En bodega; aún no puedes iniciar la entrega en ruta.'),
                _buildItemLista('• EN TRANSITO: Salió de bodega y va hacia reparto.'),
                _buildItemLista('• EN REPARTO: Asignada a ti y lista para entregar al destinatario.'),
                _buildItemLista('• LISTO PARA RECOGER: Paquete listo en sucursal (cuando aplica recogida en sucursal).'),
                _buildItemLista('• ENTREGADO EN SUCURSAL: Entregado en sucursal; puede faltar entrega final al cliente.'),
                _buildItemLista('• ENTREGADO: Entrega completada al destinatario.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Órdenes de recogida (recolectores):'),
                _buildItemLista('• POR RECOGER, EN CAMINO, RECOGIDO: flujo para recoger paquetes del cliente.'),
                const SizedBox(height: 12),
                _buildSubTitulo('¿Cuándo puedo trabajar una orden?'),
                _buildTexto(
                  'Las órdenes en "POR ENVIAR" suelen estar bloqueadas hasta que la empresa las pase a '
                  '"EN TRANSITO" o "EN REPARTO". Si ves "LISTO PARA RECOGER", sigue el flujo de sucursal '
                  'indicado en la tarjeta de la orden.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 2: Proceso de Entrega
            _buildSeccionExpandible(
              indice: 2,
              titulo: '2. Proceso de Entrega',
              icono: Icons.check_circle,
              contenido: [
                _buildSubTitulo('Pasos para Entregar una Orden:'),
                _buildItemLista('1. Asegúrate de que la orden esté en estado "EN REPARTO" (o pásala desde EN TRANSITO / ATRASADO).'),
                _buildItemLista('2. Ve al destino con "Navegar" en la tarjeta, o usa "Ver Ruta Optimizada" si llevas varias (sección 8).'),
                _buildItemLista('3. Al llegar, presiona "Entregar" o abre el detalle de la orden.'),
                _buildItemLista('4. Completa la entrega: toma foto, solicita firma si es necesario.'),
                _buildItemLista('5. Si requiere pago, cobra el monto indicado.'),
                _buildItemLista('6. Confirma la entrega.'),
                _buildItemLista('7. Si es compra de tienda, usa "Ver productos" para revisar qué debe llevar el paquete (sección 12).'),
                const SizedBox(height: 12),
                _buildSubTitulo('Fotografía de Entrega:'),
                _buildTexto(
                  'Es importante tomar una foto clara del paquete en el lugar de entrega. '
                  'Esto sirve como comprobante para la empresa y el destinatario.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Firma del Destinatario:'),
                _buildTexto(
                  'Si la orden requiere firma, el destinatario debe firmar en la pantalla. '
                  'Esta firma queda registrada como comprobante de recepción.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Remesas y entrega en sucursal:'),
                _buildTexto(
                  'Algunas órdenes son remesas o tienen entrega en sucursal. La app te guía con textos '
                  'y pasos específicos (monto, sucursal, entrega al destinatario). Sigue siempre lo que '
                  'indica la tarjeta de la orden.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Sin conexión al entregar:'),
                _buildTexto(
                  'Puedes completar la entrega sin internet: foto, firma y cambio de estado se guardan '
                  'en el teléfono y se envían solos cuando vuelva la señal (ver sección 4).',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 3: Gestión de Órdenes
            _buildSeccionExpandible(
              indice: 3,
              titulo: '3. Gestión de Órdenes',
              icono: Icons.inventory_2,
              contenido: [
                _buildSubTitulo('Pestañas Repartidor / Viajes:'),
                _buildTexto(
                  'Arriba de la pantalla principal hay dos pestañas: "Repartidor" (paquetes y envíos) '
                  'y "Viajes" (taxi). Si Viajes está bloqueado, configura primero "Ajustes de taxis" en Mi Perfil '
                  '(sección 11).',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Pantalla principal (Repartidor):'),
                _buildTexto(
                  'En la pestaña Repartidor ves tu carga de trabajo. Usa los filtros superiores '
                  '(Activas, Entregadas, Urgentes, Atrasadas) para organizarte.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Búsqueda rápida:'),
                _buildTexto(
                  'El buscador filtra por número de orden, destinatario, dirección, teléfono, estado '
                  'y datos de sucursal. Escribe unas letras y la lista se actualiza sola.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Detalles de una Orden:'),
                _buildTexto(
                  'Toca una tarjeta para ver dirección, destinatario, teléfono, notas, cobros y '
                  'acciones (navegar, explorar, entregar). En compras de tienda verás "Ver productos".',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Notificaciones y campana:'),
                _buildItemLista('• Icono de campana: avisos de nuevas órdenes o cambios importantes.'),
                _buildItemLista('• También puedes recibir notificaciones push en el teléfono (si están activadas).'),
                _buildItemLista('• Las solicitudes de viaje (taxi) llegan con un aviso especial para aceptar o rechazar.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Cambios pendientes de subir:'),
                _buildTexto(
                  'Si entregaste sin internet, un indicador puede mostrar operaciones pendientes. '
                  'No cierres la app hasta que se sincronicen o recuperes buena señal.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Escáner QR:'),
                _buildTexto(
                  'Desde el menú superior puedes abrir el escáner para localizar o validar órdenes '
                  'rápidamente en bodega o en ruta (según lo configure tu empresa).',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Órdenes Urgentes y Atrasadas:'),
                _buildTexto(
                  'Usa el filtro "Urgentes" o "Atrasadas" para priorizar. En Ruta Optimizada también '
                  'puedes priorizar urgentes/atrasadas desde el mapa (sección 8).',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 4: Conexión a Internet
            _buildSeccionExpandible(
              indice: 4,
              titulo: '4. Conexión a Internet',
              icono: Icons.wifi,
              contenido: [
                _buildSubTitulo('¿Qué puedo hacer CON internet?'),
                _buildItemLista('• Ver y actualizar órdenes en tiempo real'),
                _buildItemLista('• Descargar la lista del día a la caché al abrir la app (pantalla de carga)'),
                _buildItemLista('• Sincronizar cambios con la empresa'),
                _buildItemLista('• Recibir nuevas órdenes y solicitudes de viaje (taxi)'),
                _buildItemLista('• Mejorar la ruta en el mapa con navegación por calles'),
                _buildItemLista('• Buscar viajes, aceptar/rechazar y completar trayectos'),
                _buildItemLista('• Solicitar liquidaciones y pagar comisiones de taxi'),
                const SizedBox(height: 12),
                _buildSubTitulo('¿Qué puedo hacer SIN internet?'),
                _buildItemLista('• Ver las órdenes ya guardadas en el teléfono (no desaparecen por falta de señal).'),
                _buildItemLista('• Consultar detalle, destinatario, dirección y coordenadas en caché.'),
                _buildItemLista('• Usar "Ver Ruta Optimizada" con el mapa de la app (descargado al boot), "Ir a esta parada", ETA y avance de paradas — sin Google Maps.'),
                _buildItemLista('• Marcar EN REPARTO / entregas / firmas / fotos (quedan en cola local).'),
                _buildItemLista('• Ver productos de compras de tienda si ya se descargaron al iniciar el turno.'),
                _buildItemLista('• Revisar chat guardado localmente.'),
                _buildItemLista('• Ver perfil y datos básicos desde caché.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Qué NO funciona bien sin señal:'),
                _buildItemLista('• Recibir nuevas órdenes o nuevas llamadas de viaje.'),
                _buildItemLista('• Buscar / aceptar viajes de taxi en tiempo real (necesitas conexión).'),
                _buildItemLista('• Geocodificar direcciones nuevas que aún no tienen latitud/longitud guardada.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Aviso al perder conexión:'),
                _buildTexto(
                  'La app puede mostrarte un mensaje cuando detecta que estás sin internet, '
                  'para que sepas que estás en modo offline.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Sincronización Automática:'),
                _buildTexto(
                  'Al recuperar la conexión, la app envía entregas, fotos, firmas y cambios de estado '
                  'pendientes. Si el servidor responde vacío por un error momentáneo, se mantienen '
                  'las órdenes que ya tenías cargadas hasta tener datos nuevos.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Recomendación:'),
                _buildTexto(
                  'Abre la app con buena señal al iniciar el turno: la pantalla de carga descarga '
                  'órdenes (y productos de tienda cuando aplica) a la caché. Así puedes seguir '
                  'trabajando en zonas con mala cobertura.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 5: Solicitud de Pagos
            _buildSeccionExpandible(
              indice: 5,
              titulo: '5. Solicitud de Pagos',
              icono: Icons.payment,
              contenido: [
                _buildSubTitulo('Dos conceptos distintos'),
                _buildItemLista(
                  '• Cobro en entrega: dinero que el DESTINATARIO te paga al recibir (si la orden lo indica).',
                ),
                _buildItemLista(
                  '• Liquidación / nómina: lo que la EMPRESA te paga a ti por tus entregas (solicitas desde el perfil).',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Cobro al destinatario (si aplica)'),
                _buildTexto(
                  'Algunas órdenes muestran un monto a cobrar en la tarjeta. Verifícalo antes de entregar, '
                  'recíbelo según lo indique la empresa y completa el flujo en la app (foto/firma si aplica).',
                ),
                _buildItemLista('1. Abre la orden y confirma el monto a cobrar.'),
                _buildItemLista('2. Al entregar, indica el monto al destinatario.'),
                _buildItemLista('3. Recibe el pago según las instrucciones de tu empresa.'),
                _buildItemLista('4. Confirma en la app lo que el flujo te pida (no inventes montos).'),
                const SizedBox(height: 12),
                _buildSubTitulo('Solicitar liquidación a la empresa'),
                _buildTexto(
                  'Cuando hayas acumulado entregas listadas para cobro, ve a Mi Perfil y usa '
                  'Solicitar pago (o Liquidación, según el texto de tu app). Verás el saldo o resumen '
                  'disponible y envías la solicitud. La empresa la recibe en Nóminas → Repartidores '
                  'del panel web: puede aceptar, ajustar monto/moneda y luego registrar que ya te pagó.',
                ),
                _buildItemLista('1. Mi Perfil → Solicitar pago / liquidación.'),
                _buildItemLista('2. Revisa el resumen de entregas o monto sugerido.'),
                _buildItemLista('3. Envía la solicitud y espera la confirmación de la empresa.'),
                _buildItemLista('4. No cierres sesión a medias si hay entregas offline pendientes de sincronizar.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Estados que verás'),
                _buildItemLista('• Pendiente: la empresa aún no aceptó o no registró el pago.'),
                _buildItemLista('• Aceptada / en proceso: ya la revisaron; puede faltar el pago en efectivo o transferencia.'),
                _buildItemLista('• Pagada / registrada: la empresa confirmó que ya te liquidó.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Historial de pagos'),
                _buildTexto(
                  'En Mi Perfil → Historial de pagos consultas solicitudes anteriores, montos y fechas. '
                  'Úsalo para aclarar dudas con la empresa (comparte el monto y la fecha de la solicitud).',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Avisos'),
                _buildTexto(
                  'Puedes recibir notificaciones push cuando te asignen órdenes o cuando la empresa '
                  'responda. El chat interno con la empresa (sección 9) sirve para coordinar, pero la '
                  'liquidación formal se hace con Solicitar pago + Nóminas en el panel.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 6: Perfil y Configuración
            _buildSeccionExpandible(
              indice: 6,
              titulo: '6. Perfil y Configuración',
              icono: Icons.person,
              contenido: [
                _buildSubTitulo('Editar Mi Perfil:'),
                _buildItemLista('1. Ve a "Mi Perfil" desde el menú.'),
                _buildItemLista('2. Toca el icono de lápiz (esquina superior derecha).'),
                _buildItemLista('3. Modifica tu nombre, teléfono o email.'),
                _buildItemLista('4. Guarda los cambios.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Cambiar Foto de Perfil:'),
                _buildItemLista('1. Entra en modo edición de perfil.'),
                _buildItemLista('2. Toca el icono de cámara sobre tu foto.'),
                _buildItemLista('3. Selecciona una foto de tu galería o toma una nueva.'),
                _buildItemLista('4. La foto se actualizará automáticamente.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Cambiar Contraseña:'),
                _buildItemLista('1. En "Mi Perfil", toca "Cambiar Contraseña".'),
                _buildItemLista('2. Ingresa tu contraseña actual.'),
                _buildItemLista('3. Ingresa tu nueva contraseña (mínimo 6 caracteres).'),
                _buildItemLista('4. Confirma la nueva contraseña.'),
                _buildItemLista('5. Guarda los cambios.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Guía de Ayuda:'),
                _buildTexto(
                  'En "Mi Perfil" (icono de ayuda) abres esta guía con todos los procesos actualizados.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Ajustes de taxis (si tu empresa usa Viajes):'),
                _buildItemLista('1. Entra a Mi Perfil → Ajustes de taxis.'),
                _buildItemLista('2. Configura tu tarifa, plazas del vehículo y datos del auto (foto, placa, etc.).'),
                _buildItemLista('3. Guarda. Sin esta configuración, la pestaña Viajes no se activa.'),
                _buildItemLista('4. Desde ahí también gestionas la fianza de viajes cash (sección 11): el dinero reservado para que la empresa cobre su comisión cuando el pasajero te paga en efectivo.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Cerrar Sesión:'),
                _buildTexto(
                  'Para cerrar sesión, ve a "Mi Perfil" y toca el botón "Cerrar Sesión" '
                  'al final de la pantalla. Evita cerrar sesión si hay entregas offline '
                  'aún pendientes de sincronizar.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 7: Localización GPS
            _buildSeccionExpandible(
              indice: 7,
              titulo: '7. Localización GPS',
              icono: Icons.location_on,
              contenido: [
                _buildSubTitulo('¿Por qué es importante activar la localización?'),
                _buildTexto(
                  'La empresa necesita conocer tu ubicación en tiempo real para:',
                ),
                _buildItemLista('• Monitorear el progreso de las entregas'),
                _buildItemLista('• Ordenar la Ruta Optimizada desde tu posición'),
                _buildItemLista('• Asignar órdenes cercanas a tu ubicación'),
                _buildItemLista('• Buscar y atender Viajes (taxi): el pasajero ve tu avance'),
                _buildItemLista('• Estimaciones de llegada y trazabilidad'),
                const SizedBox(height: 12),
                _buildSubTitulo('Cómo Activar la Localización:'),
                _buildItemLista('1. La app solicitará permisos de ubicación al iniciar.'),
                _buildItemLista('2. Acepta los permisos cuando se soliciten.'),
                _buildItemLista('3. Asegúrate de tener el GPS activado en tu dispositivo.'),
                _buildItemLista('4. Con entregas o con "Buscando viajes" activo, mantén la ubicación encendida.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Privacidad:'),
                _buildTexto(
                  'Tu ubicación la usa la empresa para operación (entregas y viajes). '
                  'Cuando no estés trabajando, puedes desactivar el GPS y dejar de buscar viajes.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 8: Ruta Optimizada
            _buildSeccionExpandible(
              indice: 8,
              titulo: '8. Ruta Optimizada',
              icono: Icons.route,
              contenido: [
                _buildSubTitulo('¿Qué es la Ruta Optimizada?'),
                _buildTexto(
                  'Cuando tienes varias órdenes, "Ver Ruta Optimizada" abre un mapa con las paradas '
                  'numeradas en el mejor orden (por distancia desde tu ubicación). El flujo es directo: '
                  'sin modales de ida y vuelta ni volver a la primera orden al terminar.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Cómo usarla (flujo actual):'),
                _buildItemLista('1. En Repartidor, toca "Ver Ruta Optimizada".'),
                _buildItemLista('2. La ruta se inicia sola: verás paradas en orden en el mapa.'),
                _buildItemLista('3. "Ir a esta parada": centra el mapa en la entrega actual y la marca EN REPARTO si hace falta.'),
                _buildItemLista('4. Al llegar, usa "Entregar" para foto/firma/cobro.'),
                _buildItemLista('5. "Siguiente" pasa a la siguiente parada; en la última, "Finalizar" te regresa al inicio.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Sin internet en la ruta:'),
                _buildTexto(
                  'No necesitas Google Maps. Al iniciar el turno con señal, la app descarga el mapa '
                  'de tu zona (MBTiles de la empresa) y teselas alrededor de tus entregas. '
                  'Offline verás el mapa, las paradas numeradas y la ruta estimada dentro de la app. '
                  'Abrir en app externa es solo opcional y sí requiere internet.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Urgentes / atrasadas:'),
                _buildTexto(
                  'Si hay órdenes urgentes o atrasadas, puedes priorizarlas desde un aviso en el mapa. '
                  'Si no, el orden sigue la distancia más eficiente.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Controles útiles:'),
                _buildItemLista('• Icono de ubicación: centra el mapa en ti'),
                _buildItemLista('• Icono de ruta: encaja todas las paradas en pantalla'),
                _buildItemLista('• Abrir en app externa (opcional): Google Maps u otra, si lo prefieres'),
                const SizedBox(height: 12),
                _buildSubTitulo('Estados en la Ruta:'),
                _buildTexto(
                  'La ruta incluye órdenes activas listas para reparto. Las "POR ENVIAR" normalmente '
                  'no entran hasta que la empresa las active. Las ENTREGADO / CANCELADA salen del mapa.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 9: Chat con la Empresa
            _buildSeccionExpandible(
              indice: 9,
              titulo: '9. Chat con la Empresa',
              icono: Icons.chat_bubble_outline,
              contenido: [
                _buildSubTitulo('¿Para qué sirve?'),
                _buildTexto(
                  'Puedes escribir a la empresa (administración o soporte) sin salir de la app. '
                  'Úsalo para dudas de una orden, retrasos, incidencias o coordinación del día.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Cómo abrir el chat:'),
                _buildItemLista('1. En la pantalla principal, toca el icono de chat (burbuja) arriba.'),
                _buildItemLista('2. Elige la conversación con tu empresa.'),
                _buildItemLista('3. Escribe el mensaje o adjunta una foto si hace falta.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Mensajes y avisos:'),
                _buildItemLista('• Un punto o número rojo indica mensajes nuevos sin leer.'),
                _buildItemLista('• Al entrar a una conversación, los mensajes se marcan como leídos.'),
                _buildItemLista('• Puedes recibir sonido o notificación cuando llega un mensaje de la empresa.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Sin internet:'),
                _buildTexto(
                  'Puedes leer mensajes guardados en el teléfono. Los que envíes sin conexión '
                  'se enviarán cuando vuelva la señal.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 10: Master, Recolector y Remesas
            _buildSeccionExpandible(
              indice: 10,
              titulo: '10. Master, Recolector y Remesas',
              icono: Icons.badge_outlined,
              contenido: [
                _buildSubTitulo('Repartidor normal:'),
                _buildTexto(
                  'Ves las órdenes de envío asignadas a tu nombre. El filtro "Activas" muestra el trabajo '
                  'pendiente; "Entregadas" el historial reciente del día.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Repartidor Master:'),
                _buildItemLista('• Puede ver órdenes de más repartidores del mismo equipo (según la empresa).'),
                _buildItemLista('• Filtro "MÍAS": solo tus asignaciones.'),
                _buildItemLista('• Sin "MÍAS": ves la carga del equipo para coordinar.'),
                _buildItemLista('• Si la empresa lo permite, también ve recogidas en sucursal pendientes.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Recolector:'),
                _buildTexto(
                  'Si tu cuenta es tipo recolector, la app muestra órdenes de RECOGIDA con estados '
                  'POR RECOGER, EN CAMINO y RECOGIDO. El flujo es recoger paquetes del cliente, '
                  'no entrega a domicilio.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Remesas:'),
                _buildTexto(
                  'Las remesas pueden tener pasos y montos distintos. Revisa siempre el detalle '
                  'antes de cobrar o marcar entregado. Algunas combinan sucursal y entrega final al destinatario.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Órdenes de tienda por vendedor:'),
                _buildTexto(
                  'Las entregas gestionadas por un vendedor/colaborador en la tienda web pueden no '
                  'aparecerte en tu lista: las lleva quien vendió el producto, no el repartidor de envíos. '
                  'Si sí te las asignan, usa "Ver productos" (sección 12).',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('También puedes hacer Viajes (taxi):'),
                _buildTexto(
                  'Si tu empresa lo activa, además de paquetes puedes atender viajes en la pestaña '
                  '"Viajes" (sección 11). La suspensión de viajes no bloquea tus entregas de paquetería.',
                ),
              ],
            ),
            
            const SizedBox(height: 12),

            // Sección 11: Viajes (Taxi)
            _buildSeccionExpandible(
              indice: 11,
              titulo: '11. Viajes (Taxi)',
              icono: Icons.local_taxi,
              contenido: [
                _buildSubTitulo('¿Qué es la pestaña Viajes?'),
                _buildTexto(
                  'Es el modo chofer de la misma app. Atiendes solicitudes de pasajeros de tu empresa: '
                  'mapa, búsqueda de viajes, aceptación y navegación hasta el destino.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Activar Viajes (una sola vez):'),
                _buildItemLista('1. Mi Perfil → Ajustes de taxis.'),
                _buildItemLista('2. Define tu tarifa (precio por distancia), plazas y datos del vehículo.'),
                _buildItemLista('3. Guarda. Luego podrás abrir la pestaña Viajes en la pantalla principal.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Buscar viajes:'),
                _buildItemLista('1. Cambia a la pestaña "Viajes".'),
                _buildItemLista('2. Activa "Buscando viajes" (punto verde = estás disponible).'),
                _buildItemLista('3. Mantén el GPS activo; sin ubicación no puedes buscar.'),
                _buildItemLista('4. Cuando llegue una solicitud, verás el aviso para Aceptar o Rechazar.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Flujo del viaje (después de aceptar):'),
                _buildItemLista('1. Hacia el pasajero → botón "Llegada" cuando estés en el punto de recogida.'),
                _buildItemLista('2. Esperando al pasajero → "Iniciar viaje" al subir.'),
                _buildItemLista('3. Hacia el destino → "Completar viaje" al terminar.'),
                _buildItemLista('4. Puedes cancelar solo antes de iniciar el trayecto al destino (según reglas de la empresa).'),
                _buildItemLista('5. Si cierras la app con un viaje activo, al volver te avisará para continuar el mapa.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Chat del viaje:'),
                _buildTexto(
                  'Durante el viaje puedes escribir al pasajero desde el mapa del trayecto '
                  '(icono de chat). Úsalo para coordinar llegada o cambios de punto.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('¿Qué es el saldo de fianza? (léelo si eres nuevo)'),
                _buildTexto(
                  'Imagina que un pasajero te paga el viaje en efectivo (cash). Ese dinero se queda '
                  'en tu bolsillo, pero la empresa igual debe cobrar su comisión de ese viaje. '
                  'Para no “deberle” a la empresa cada vez que cobras en cash, usas la fianza.',
                ),
                _buildItemLista(
                  '• La fianza es un dinero tuyo que dejas guardado en la app solo para viajes.',
                ),
                _buildItemLista(
                  '• Cuando haces un viaje pagado en cash, el sistema descuenta de la fianza '
                  'la comisión que le corresponde a la empresa.',
                ),
                _buildItemLista(
                  '• Así no te endeudas: la empresa ya cobró su parte desde tu fianza, y tú te '
                  'quedas con el efectivo del pasajero.',
                ),
                _buildItemLista(
                  '• Si la fianza se agota o acumulas comisión sin pagar, la empresa puede '
                  'bloquearte para buscar nuevos viajes hasta que recargues o liquides.',
                ),
                const SizedBox(height: 8),
                _buildTexto(
                  'Ejemplo simple: el pasajero te paga \$10 en cash. La empresa se lleva, por '
                  'ejemplo, \$1 de comisión. Ese \$1 sale de tu fianza (no del billete que tienes '
                  'en la mano). Si no tuvieras fianza, ese \$1 quedaría como deuda.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Cómo cargar y usar la fianza:'),
                _buildItemLista(
                  '1. Mi Perfil → Comisión / fianza cash.',
                ),
                _buildItemLista(
                  '2. Si tienes saldo en tu billetera (ganancias de entregas u otros), puedes '
                  'transferirlo a la fianza. Ese dinero pasa a cubrir comisiones de viajes cash.',
                ),
                _buildItemLista(
                  '3. También puedes pagar la comisión pendiente en oficina o con los métodos '
                  'que muestre la pantalla (por ejemplo Zelle, si tu empresa lo ofrece).',
                ),
                _buildItemLista(
                  '4. La transferencia a fianza no se puede “devolver” sola a la billetera: '
                  'queda para viajes y comisiones cash.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Resumen en una frase:'),
                _buildTexto(
                  'Fianza = reserva para que la app cobre la comisión de los viajes en efectivo, '
                  'y tú no te quedes debiendo a la empresa.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Viajes suspendidos:'),
                _buildTexto(
                  'Si ves "Viajes suspendidos", no puedes buscar ni aceptar viajes hasta que la empresa '
                  'te reactive. Puedes seguir usando Repartidor, chat y el resto de funciones. '
                  'Contacta a tu empresa por el chat de soporte.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Internet en Viajes:'),
                _buildTexto(
                  'Aceptar, iniciar y completar viajes requieren conexión. Sin señal no recibirás '
                  'nuevas solicitudes. Con señal débil, espera a que cargue el detalle antes de aceptar.',
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Sección 12: Compras de tienda y actualizaciones
            _buildSeccionExpandible(
              indice: 12,
              titulo: '12. Compras de tienda y actualizaciones',
              icono: Icons.shopping_bag_outlined,
              contenido: [
                _buildSubTitulo('Ver productos de una orden de tienda:'),
                _buildTexto(
                  'En órdenes de compra (tienda) aparece "Ver productos". Ahí ves el listado y fotos '
                  'de lo que el cliente compró, para validar el contenido al entregar.',
                ),
                _buildItemLista('• Con internet: se cargan al abrir o al iniciar turno.'),
                _buildItemLista('• Sin internet: se muestran si ya se descargaron a la caché del teléfono.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Actualización obligatoria de la app:'),
                _buildTexto(
                  'A veces la empresa exige una versión nueva. Verás un aviso que no permite continuar '
                  'hasta actualizar desde la tienda de aplicaciones. Es normal: evita fallos con '
                  'órdenes, viajes o sincronización.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Consejo:'),
                _buildTexto(
                  'Mantén la app actualizada y abre con buena señal al empezar el día para que '
                  'órdenes, productos y datos de perfil queden listos en caché.',
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Sección de contacto/soporte
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.botonPrincipal.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.support_agent,
                    size: 40,
                    color: AppColors.botonPrincipal,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '¿Necesitas Más Ayuda?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Si tienes dudas de entregas, Viajes (taxi), comisiones o problemas técnicos, '
                    'usa el chat de la app o contacta a tu supervisor en la empresa.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.darkTextMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSeccionExpandible({
    required int indice,
    required String titulo,
    required IconData icono,
    required List<Widget> contenido,
  }) {
    final isExpanded = _seccionesExpandidas[indice] ?? false;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded
              ? AppColors.exito.withValues(alpha: 0.55)
              : AppColors.darkBorder,
          width: isExpanded ? 1.5 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _seccionesExpandidas[indice] = expanded;
            });
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.exito.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icono,
              color: AppColors.exito,
              size: 24,
            ),
          ),
          title: Text(
            titulo,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
          trailing: Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: AppColors.exito,
            size: 28,
          ),
          collapsedIconColor: AppColors.darkTextMuted,
          iconColor: AppColors.exito,
          textColor: AppColors.darkText,
          children: contenido,
        ),
      ),
    );
  }
  
  Widget _buildSubTitulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.darkText,
        ),
      ),
    );
  }
  
  Widget _buildTexto(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.darkTextMuted,
          height: 1.5,
        ),
      ),
    );
  }
  
  Widget _buildItemLista(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.exito,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.darkTextMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

