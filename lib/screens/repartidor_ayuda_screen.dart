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
  };
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondoGeneral,
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
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF4CAF50).withOpacity(0.2),
                    const Color(0xFF4CAF50).withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF4CAF50).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.help_outline,
                    size: 48,
                    color: Color(0xFF4CAF50),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bienvenido a la Guía de Ayuda',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2C2C),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aquí encontrarás toda la información que necesitas para usar la app de repartidor de forma eficiente.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
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
                _buildSubTitulo('Estados de las Órdenes:'),
                _buildItemLista('• POR ENVIAR: La orden está en la bodega, esperando ser enviada.'),
                _buildItemLista('• EN TRANSITO: La orden ha salido de la bodega y está en camino.'),
                _buildItemLista('• EN REPARTO: La orden está contigo y lista para entregar.'),
                _buildItemLista('• ENTREGADO: La orden fue entregada exitosamente.'),
                const SizedBox(height: 12),
                _buildSubTitulo('¿Cuándo puedo recibir una orden?'),
                _buildTexto(
                  'Solo puedes recibir órdenes que estén en estado "EN TRANSITO" o "POR ENVIAR" '
                  'con repartidor asignado. Las órdenes en "POR ENVIAR" aún no han salido de la '
                  'bodega, por lo que debes esperar a que cambien a "EN TRANSITO" antes de poder '
                  'iniciar la entrega.',
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
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Sección 3: Gestión de Órdenes
            _buildSeccionExpandible(
              indice: 3,
              titulo: '3. Gestión de Órdenes',
              icono: Icons.inventory_2,
              contenido: [
                _buildSubTitulo('Ver Mis Órdenes:'),
                _buildTexto(
                  'En la pantalla principal verás todas las órdenes asignadas a ti. '
                  'Puedes filtrarlas por estado para encontrar fácilmente lo que necesitas.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Detalles de una Orden:'),
                _buildTexto(
                  'Toca cualquier orden para ver información completa: dirección, destinatario, '
                  'teléfono, notas especiales, y más.',
                ),
                const SizedBox(height: 12),
                _buildSubTitulo('Órdenes Urgentes:'),
                _buildTexto(
                  'Las órdenes marcadas como urgentes aparecen destacadas. '
                  'Debes priorizarlas en tu ruta de entrega.',
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
                _buildItemLista('• Ver órdenes previamente cargadas'),
                _buildItemLista('• Marcar entregas (se guardarán localmente)'),
                _buildItemLista('• Tomar fotos de entrega'),
                _buildItemLista('• Ver información de destinatarios'),
                _buildItemLista('• Navegar con GPS (si tienes datos móviles)'),
                const SizedBox(height: 12),
                _buildSubTitulo('Sincronización Automática:'),
                _buildTexto(
                  'Cuando recuperes la conexión, todos los cambios realizados sin internet '
                  'se sincronizarán automáticamente con la empresa.',
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
                  'Solo puedes entregar órdenes que estén en estado "EN REPARTO". '
                  'Si una orden está en "POR ENVIAR", significa que aún no ha salido de la bodega '
                  'y debes esperar a que cambie a "EN TRANSITO" o "EN REPARTO".',
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Sección de contacto/soporte
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF9800).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.support_agent,
                    size: 40,
                    color: Color(0xFFFF9800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '¿Necesitas Más Ayuda?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2C2C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Si tienes dudas adicionales o problemas técnicos, contacta a tu supervisor '
                    'o al equipo de soporte de la empresa.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded 
              ? const Color(0xFF4CAF50).withOpacity(0.5)
              : Colors.grey[300]!,
          width: isExpanded ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
              color: const Color(0xFF4CAF50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icono,
              color: const Color(0xFF4CAF50),
              size: 24,
            ),
          ),
          title: Text(
            titulo,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C2C2C),
            ),
          ),
          trailing: Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: const Color(0xFF4CAF50),
            size: 28,
          ),
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
          color: Color(0xFF37474F),
        ),
      ),
    );
  }
  
  Widget _buildTexto(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[700],
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
              color: Color(0xFF4CAF50),
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

