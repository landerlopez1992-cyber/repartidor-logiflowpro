/// Mapa de provincias y municipios de Cuba con sus códigos de identificación
/// según el Anexo No.6 del Reglamento de Mensajería Internacional de Cuba
/// (Provincias y Municipios de la República de Cuba ordenados por su
/// correspondiente código de identificación).
///
/// Formato del código HBL de 14 caracteres:
///   [3 letras corresponsal] + [4 dígitos provincia/municipio] + [7 dígitos consecutivo]
/// Ejemplo: BBB + 2301 + 0000001 = "BBB23010000001"
class CodigosCubaCubatrans {
  /// Devuelve el código de 4 dígitos para una combinación provincia/municipio.
  /// Normaliza espacios, tildes y capitalización antes de buscar.
  static String? getCodigo(String? provincia, String? municipio) {
    if (provincia == null || municipio == null) return null;
    final key = '${_norm(provincia)}|${_norm(municipio)}';
    return _codigos[key];
  }

  /// Devuelve '0000' cuando no se encuentra el código (seguro para HBL).
  static String getCodigoSafe(String? provincia, String? municipio) {
    return getCodigo(provincia, municipio) ?? '0000';
  }

  static String _norm(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');

  static final Map<String, String> _codigos = {
    // ── PINAR DEL RÍO ─────────────────────────────────────────────────────
    'pinar del rio|sandino': '2101',
    'pinar del rio|mantua': '2102',
    'pinar del rio|minas de matahambre': '2103',
    'pinar del rio|vinales': '2104',
    'pinar del rio|la palma': '2105',
    'pinar del rio|los palacios': '2106',
    'pinar del rio|consolacion del sur': '2107',
    'pinar del rio|pinar del rio': '2108',
    'pinar del rio|san luis': '2109',
    'pinar del rio|san juan y martinez': '2110',
    'pinar del rio|guanes': '2111',
    // Selector [MunicipiosCuba] usa «Guane» (sin s); mismo código Anexo 6.
    'pinar del rio|guane': '2111',

    // ── ARTEMISA ──────────────────────────────────────────────────────────
    'artemisa|bahia honda': '2201',
    'artemisa|mariel': '2202',
    'artemisa|guanajay': '2203',
    'artemisa|caimito': '2204',
    'artemisa|bauta': '2205',
    'artemisa|san antonio de los banos': '2206',
    'artemisa|guira de melena': '2207',
    'artemisa|alquizar': '2208',
    'artemisa|artemisa': '2209',
    'artemisa|candelaria': '2210',
    'artemisa|san cristobal': '2211',

    // ── LA HABANA ─────────────────────────────────────────────────────────
    'la habana|playa': '2301',
    'la habana|plaza de la revolucion': '2302',
    'la habana|centro habana': '2303',
    'la habana|la habana vieja': '2304',
    'la habana|regla': '2305',
    'la habana|la habana del este': '2306',
    'la habana|guanabacoa': '2307',
    'la habana|san miguel del padron': '2308',
    'la habana|diez de octubre': '2309',
    'la habana|cerro': '2310',
    'la habana|marianao': '2311',
    'la habana|la lisa': '2312',
    'la habana|boyeros': '2313',
    'la habana|arroyo naranjo': '2314',
    'la habana|cotorro': '2315',

    // ── MAYABEQUE ─────────────────────────────────────────────────────────
    'mayabeque|bejucal': '2401',
    'mayabeque|san jose de las lajas': '2402',
    'mayabeque|jaruco': '2403',
    'mayabeque|santa cruz del norte': '2404',
    'mayabeque|madruga': '2405',
    'mayabeque|nueva paz': '2406',
    'mayabeque|san nicolas': '2407',
    'mayabeque|guines': '2408',
    'mayabeque|melena del sur': '2409',
    'mayabeque|batabano': '2410',
    'mayabeque|quivican': '2411',

    // ── MATANZAS ──────────────────────────────────────────────────────────
    'matanzas|matanzas': '2501',
    'matanzas|cardenas': '2502',
    'matanzas|marti': '2503',
    'matanzas|colon': '2504',
    'matanzas|perico': '2505',
    'matanzas|jovellanos': '2506',
    'matanzas|pedro betancourt': '2507',
    'matanzas|limonar': '2508',
    'matanzas|union de reyes': '2509',
    'matanzas|cienaga de zapata': '2510',
    'matanzas|jaguey grande': '2511',
    'matanzas|calimete': '2512',
    'matanzas|los arabos': '2513',
    // Municipio turístico en listas actuales (Anexo 6 / desgloses ampliados).
    'matanzas|varadero': '2514',

    // ── VILLA CLARA ───────────────────────────────────────────────────────
    'villa clara|corralillo': '2601',
    'villa clara|quemado de guines': '2602',
    'villa clara|sagua la grande': '2603',
    'villa clara|encrucijada': '2604',
    'villa clara|camajuani': '2605',
    'villa clara|caibarien': '2606',
    'villa clara|remedios': '2607',
    'villa clara|placetas': '2608',
    'villa clara|santa clara': '2609',
    'villa clara|cifuentes': '2610',
    'villa clara|santo domingo': '2611',
    'villa clara|ranchuelo': '2612',
    'villa clara|manicaragua': '2613',

    // ── CIENFUEGOS ────────────────────────────────────────────────────────
    'cienfuegos|aguada de pasajeros': '2701',
    'cienfuegos|rodas': '2702',
    'cienfuegos|palmira': '2703',
    'cienfuegos|lajas': '2704',
    'cienfuegos|cruces': '2705',
    'cienfuegos|cumanayagua': '2706',
    'cienfuegos|cienfuegos': '2707',
    'cienfuegos|abreus': '2708',
    // En [MunicipiosCuba] figura este nombre (no «Abreus»); mismo anillo provincial.
    'cienfuegos|santa isabel de las lajas': '2708',

    // ── SANCTI SPÍRITUS ───────────────────────────────────────────────────
    'sancti spiritus|yaguajay': '2801',
    'sancti spiritus|jatibonico': '2802',
    'sancti spiritus|taguasco': '2803',
    'sancti spiritus|cabaiguan': '2804',
    'sancti spiritus|fomento': '2805',
    'sancti spiritus|trinidad': '2806',
    'sancti spiritus|sancti spiritus': '2807',
    'sancti spiritus|la sierpe': '2808',

    // ── CIEGO DE ÁVILA ────────────────────────────────────────────────────
    'ciego de avila|chambas': '2901',
    'ciego de avila|moron': '2902',
    'ciego de avila|bolivia': '2903',
    'ciego de avila|primero de enero': '2904',
    'ciego de avila|ciro redondo': '2905',
    'ciego de avila|florencia': '2906',
    'ciego de avila|majagua': '2907',
    'ciego de avila|ciego de avila': '2908',
    'ciego de avila|venezuela': '2909',
    // Clave ASCII: _norm() quita tildes; «baraguá» en el mapa no coincidía con el selector.
    'ciego de avila|baragua': '2910',

    // ── CAMAGÜEY ──────────────────────────────────────────────────────────
    'camaguey|carlos manuel de cespedes': '3001',
    // [MunicipiosCuba]: «Carlos M. de Céspedes» (abreviatura oficial).
    'camaguey|carlos m. de cespedes': '3001',
    'camaguey|esmeralda': '3002',
    'camaguey|sierra de cubitas': '3003',
    'camaguey|minas': '3004',
    'camaguey|nuevitas': '3005',
    'camaguey|guaimaro': '3006',
    'camaguey|sibanicu': '3007',
    'camaguey|camaguey': '3008',
    'camaguey|florida': '3009',
    'camaguey|vertientes': '3010',
    'camaguey|jimaguayu': '3011',
    'camaguey|najasa': '3012',
    'camaguey|santa cruz del sur': '3013',

    // ── LAS TUNAS ─────────────────────────────────────────────────────────
    'las tunas|manati': '3101',
    'las tunas|puerto padre': '3102',
    'las tunas|jesus menendez': '3103',
    'las tunas|majibacoa': '3104',
    'las tunas|las tunas': '3105',
    'las tunas|jobabo': '3106',
    'las tunas|colombia': '3107',
    'las tunas|amancio': '3108',

    // ── HOLGUÍN ───────────────────────────────────────────────────────────
    'holguin|gibara': '3201',
    'holguin|rafael freyre': '3202',
    'holguin|banes': '3203',
    'holguin|antilla': '3204',
    'holguin|baguanos': '3205',
    'holguin|holguin': '3206',
    'holguin|calixto garcia': '3207',
    'holguin|cacocum': '3208',
    'holguin|urbano noris': '3209',
    'holguin|cueto': '3210',
    'holguin|mayari': '3211',
    'holguin|frank pais': '3212',
    'holguin|sagua de tanamo': '3213',
    'holguin|moa': '3214',

    // ── GRANMA ────────────────────────────────────────────────────────────
    'granma|rio cauto': '3301',
    'granma|cauto cristo': '3302',
    'granma|jiguani': '3303',
    'granma|bayamo': '3304',
    'granma|yara': '3305',
    'granma|manzanillo': '3306',
    'granma|campechuela': '3307',
    'granma|media luna': '3308',
    'granma|niquero': '3309',
    'granma|pilon': '3310',
    'granma|bartolome maso': '3311',
    'granma|buey arriba': '3312',
    'granma|guisa': '3313',

    // ── SANTIAGO DE CUBA ──────────────────────────────────────────────────
    'santiago de cuba|contramaestre': '3401',
    'santiago de cuba|mella': '3402',
    // [MunicipiosCuba]: nombre completo del municipio.
    'santiago de cuba|julio antonio mella': '3402',
    'santiago de cuba|san luis': '3403',
    'santiago de cuba|segundo frente': '3404',
    'santiago de cuba|songo - la maya': '3405',
    'santiago de cuba|songo la maya': '3405',
    // [MunicipiosCuba]: «Songo-La Maya» (guión sin espacios).
    'santiago de cuba|songo-la maya': '3405',
    'santiago de cuba|santiago de cuba': '3406',
    'santiago de cuba|palma soriano': '3407',
    'santiago de cuba|tercer frente': '3408',
    'santiago de cuba|guama': '3409',

    // ── GUANTÁNAMO ────────────────────────────────────────────────────────
    'guantanamo|el salvador': '3501',
    'guantanamo|manuel tames': '3502',
    'guantanamo|yateras': '3503',
    'guantanamo|baracoa': '3504',
    'guantanamo|maisi': '3505',
    'guantanamo|imias': '3506',
    'guantanamo|san antonio del sur': '3507',
    'guantanamo|caimanera': '3508',
    'guantanamo|guantanamo': '3509',
    'guantanamo|niceto perez': '3510',

    // ── ISLA DE LA JUVENTUD ───────────────────────────────────────────────
    'isla de la juventud|municipio especial isla de la juventud': '3601',
    'isla de la juventud|nueva gerona': '3601',
    'isla de la juventud|isla de la juventud': '3601',
    'isla de la juventud|la demajagua': '3602',
  };
}
