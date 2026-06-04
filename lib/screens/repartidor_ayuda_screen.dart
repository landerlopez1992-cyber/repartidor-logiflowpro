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
                    'Aquí encontrarás toda la información que necesitas para usar la app de repartidor de forma eficiente.',
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
                _buildItemLista('1. Asegúrate de que la orden esté en estado "EN REPARTO".'),
                _buildItemLista('2. Usa el botón "Navegar" para abrir GPS y llegar al destino.'),
                _buildItemLista('3. Al llegar, presiona "Entregar" o "Explorar Orden".'),
                _buildItemLista('4. Completa la entrega: toma foto, solicita firma si es necesario.'),
                _buildItemLista('5. Si requiere pago, cobra el monto indicado.'),
                _buildItemLista('6. Confirma la entrega.'),
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
                _buildSubTitulo('Pantalla principal:'),
                _buildTexto(
                  'En la pantalla de órdenes ves tu carga de trabajo. Usa los filtros superiores '
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
                  'acciones (navegar, explorar, entregar).',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Notificaciones y campana:'),
                _buildItemLista('• Icono de campana: avisos de nuevas órdenes o cambios importantes.'),
                _buildItemLista('• También puedes recibir notificaciones push en el teléfono (si están activadas).'),
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
                  'Usa el filtro "Urgentes" o "Atrasadas" para priorizar. Las urgentes suelen ir '
                  'destacadas en la lista.',
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
                _buildItemLista('• Sincronizar cambios con la empresa'),
                _buildItemLista('• Recibir nuevas órdenes asignadas'),
                _buildItemLista('• Actualizar estado de entregas'),
                _buildItemLista('• Ver mapa y rutas optimizadas'),
                _buildItemLista('• Solicitar pagos'),
                const SizedBox(height: 12),
                _buildSubTitulo('¿Qué puedo hacer SIN internet?'),
                _buildItemLista('• Ver las órdenes que ya se guardaron en el teléfono (no desaparecen por falta de señal).'),
                _buildItemLista('• Seguir consultando detalle, destinatario y dirección en caché.'),
                _buildItemLista('• Marcar entregas, firmas y fotos (quedan en cola local).'),
                _buildItemLista('• Revisar conversaciones de chat guardadas localmente.'),
                _buildItemLista('• Ver perfil y datos básicos desde caché.'),
                _buildItemLista('• Navegar con GPS si el mapa del teléfono tiene datos móviles.'),
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
                  'Abre la app con buena señal al iniciar el turno para descargar la lista del día. '
                  'Así trabajarás mejor si más tarde entras a zonas con mala cobertura.',
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
                _buildSubTitulo('¿Cuándo debo cobrar?'),
                _buildTexto(
                  'Algunas órdenes requieren que cobres un monto al momento de la entrega. '
                  'Esto se indica claramente en los detalles de la orden.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Proceso de Cobro:'),
                _buildItemLista('1. Verifica el monto a cobrar en la orden.'),
                _buildItemLista('2. Al entregar, indica al destinatario el monto.'),
                _buildItemLista('3. Recibe el pago.'),
                _buildItemLista('4. Marca la orden como "Pagado" en la app.'),
                _buildItemLista('5. Registra el método de pago (efectivo, transferencia, etc.).'),
                const SizedBox(height: 12),
                _buildSubTitulo('Solicitar Pago a la Empresa:'),
                _buildTexto(
                  'En tu perfil, puedes solicitar el pago de tus entregas. '
                  'Ve a "Mi Perfil" > "Solicitar Pago" para ver tu saldo disponible '
                  'y enviar la solicitud a la empresa.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Historial de Pagos:'),
                _buildTexto(
                  'Puedes ver el historial completo de todos los pagos recibidos en la sección '
                  '"Historial de Pagos" de tu perfil.',
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
                _buildSubTitulo('Cerrar Sesión:'),
                _buildTexto(
                  'Para cerrar sesión, ve a "Mi Perfil" y toca el botón "Cerrar Sesión" '
                  'al final de la pantalla.',
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
                _buildItemLista('• Optimizar rutas de entrega'),
                _buildItemLista('• Asignar órdenes cercanas a tu ubicación'),
                _buildItemLista('• Proporcionar estimaciones de llegada a los destinatarios'),
                _buildItemLista('• Mejorar la seguridad y trazabilidad'),
                const SizedBox(height: 12),
                _buildSubTitulo('Cómo Activar la Localización:'),
                _buildItemLista('1. La app solicitará permisos de ubicación al iniciar.'),
                _buildItemLista('2. Acepta los permisos cuando se soliciten.'),
                _buildItemLista('3. Asegúrate de tener el GPS activado en tu dispositivo.'),
                _buildItemLista('4. La localización se activa automáticamente cuando inicias una entrega.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Privacidad:'),
                _buildTexto(
                  'Tu ubicación solo es visible para la empresa durante tus horas de trabajo '
                  'y cuando tienes órdenes activas. Puedes desactivarla cuando no estés trabajando.',
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
                  'Cuando tienes 2 o más órdenes para entregar, puedes usar la función de '
                  'Ruta Optimizada. Esta calcula el mejor orden de entrega para ahorrar tiempo y combustible.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Cómo Usar la Ruta Optimizada:'),
                _buildItemLista('1. Asegúrate de tener al menos 2 órdenes asignadas.'),
                _buildItemLista('2. Toca el botón "Ver Ruta Optimizada" en la pantalla principal.'),
                _buildItemLista('3. Verás un mapa con todas las entregas numeradas.'),
                _buildItemLista('4. Sigue el orden sugerido para máxima eficiencia.'),
                _buildItemLista('5. Usa los botones + y - para acercar/alejar el mapa.'),
                const SizedBox(height: 12),
                _buildSubTitulo('Controles del Mapa:'),
                _buildItemLista('• Botón +: Acerca el mapa para ver más detalle'),
                _buildItemLista('• Botón -: Aleja el mapa para ver más área'),
                _buildItemLista('• Icono de objetivo: Centra el mapa en tu ubicación'),
                _buildItemLista('• Botón "Navegar": Abre GPS para la orden actual'),
                const SizedBox(height: 12),
                _buildSubTitulo('Estados en la Ruta:'),
                _buildTexto(
                  'La ruta incluye órdenes listas para reparto. Las que siguen en "POR ENVIAR" '
                  'normalmente no forman parte del recorrido hasta que la empresa las active.',
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
                  'aparecerte en tu lista: las lleva quien vendió el producto, no el repartidor de envíos.',
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
                    'Si tienes dudas adicionales o problemas técnicos, usa el chat de la app '
                    'o contacta a tu supervisor en la empresa.',
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

