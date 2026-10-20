/// Intérprete local de órdenes en español (funciona sin internet).
///
/// Convierte frases como "avanza 30 centímetros, gira a la derecha y saluda"
/// en instrucciones del protocolo del robot: `f-30-cm;r-90-g;g`.
///
/// También se usa para leer la respuesta de Gemini: se le pide a Gemini que
/// reescriba la orden en frases simples ("adelante 30 cm, derecha 90 grados")
/// y luego este mismo intérprete las convierte en instrucciones.
library;

/// Tipo de paso, usado por la interfaz para elegir icono y color.
enum StepKind { move, turn, claw, stop, social, emotion, speak }

class RobotStep {
  const RobotStep(this.code, this.label, this.kind);

  /// Instrucción que entiende el robot (p. ej. `f-20-cm`).
  final String code;

  /// Texto para mostrar en la app (p. ej. "Adelante 20 cm").
  final String label;
  final StepKind kind;

  @override
  String toString() => '$label [$code]';
}

class ParsedCommand {
  const ParsedCommand(this.steps);

  final List<RobotStep> steps;

  bool get isEmpty => steps.isEmpty;

  /// Cadena lista para enviar después de `text:`.
  String get instructions => steps.map((s) => s.code).join(';');
}

// --------------------------------------------------------------------------
// Normalización

const _accents = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
};

String _stripAccents(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

List<String> _words(String clause) => _stripAccents(clause.toLowerCase())
    .replaceAll(RegExp(r'[^a-z0-9.,°\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

// --------------------------------------------------------------------------
// Números escritos con palabras

const _numberWords = <String, double>{
  'un': 1, 'uno': 1, 'una': 1, 'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5,
  'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10, 'once': 11,
  'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15, 'dieciseis': 16,
  'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19, 'veinte': 20,
  'veintiuno': 21, 'veintidos': 22, 'veintitres': 23, 'veinticuatro': 24,
  'veinticinco': 25, 'veintiseis': 26, 'veintisiete': 27, 'veintiocho': 28,
  'veintinueve': 29, 'treinta': 30, 'cuarenta': 40, 'cincuenta': 50,
  'sesenta': 60, 'setenta': 70, 'ochenta': 80, 'noventa': 90, 'cien': 100,
  'ciento': 100, 'doscientos': 200, 'trescientos': 300, 'medio': 0.5,
  'media': 0.5,
};

double? _numberAt(List<String> w, int i) {
  final token = w[i].replaceAll(',', '.');
  final digits = double.tryParse(token.replaceAll(RegExp(r'[^0-9.]'), ''));
  if (digits != null && RegExp(r'^[0-9]').hasMatch(token)) return digits;
  return _numberWords[w[i]];
}

/// Busca el primer número de la frase (con su unidad, si la hay).
({double value, String? unit})? _quantity(List<String> w) {
  for (var i = 0; i < w.length; i++) {
    var value = _numberAt(w, i);
    if (value == null) continue;
    // "un" / "una" solos ("da una vuelta") no son cantidades si no hay unidad
    var j = i + 1;
    // "treinta y cinco"
    if (j + 1 < w.length && w[j] == 'y' && value >= 20 && value % 10 == 0) {
      final extra = _numberWords[w[j + 1]];
      if (extra != null && extra < 10) {
        value += extra;
        j += 2;
      }
    }
    // la unidad puede venir pegada: "20cm", "90°"
    final glued = RegExp(r'^[0-9.,]+([a-z°]+)$').firstMatch(w[i]);
    String? unit = glued != null ? _unit(glued.group(1)!) : null;
    if (unit == null && j < w.length) {
      unit = _unit(w[j]);
      if (unit != null) j++;
    }
    // "un metro y medio" (el preprocesado lo convierte en el token "ymedio")
    if (unit != null && j < w.length && w[j] == 'ymedio') {
      value += 0.5;
    }
    if ((w[i] == 'un' || w[i] == 'una') && unit == null) continue;
    return (value: value, unit: unit);
  }
  return null;
}

String? _unit(String word) {
  if (word == 'cm' || word.startsWith('centimetro')) return 'cm';
  if (word == 'm' || word == 'mt' || word == 'mts' || word.startsWith('metro')) return 'm';
  if (word == 's' || word == 'seg' || word == 'segs' || word.startsWith('segundo')) return 's';
  if (word == '°' || word == 'g' || word.startsWith('grado')) return 'g';
  if (word.startsWith('paso')) return 'paso';
  return null;
}

// --------------------------------------------------------------------------
// Palabras clave

bool _hasAny(List<String> w, Iterable<String> keys) => keys.any(w.contains);

bool _hasPrefix(List<String> w, Iterable<String> prefixes) =>
    w.any((word) => prefixes.any(word.startsWith));

bool _hasPhrase(String normalized, Iterable<String> phrases) =>
    phrases.any((p) => normalized.contains(p));

const _emotions = <String, (String code, String label)>{
  'feliz': ('feliz', 'Feliz'), 'contento': ('feliz', 'Feliz'), 'contenta': ('feliz', 'Feliz'),
  'alegre': ('feliz', 'Feliz'), 'triste': ('triste', 'Triste'),
  'sorprendido': ('sorprendido', 'Sorprendido'), 'sorprendida': ('sorprendido', 'Sorprendido'),
  'sorpresa': ('sorprendido', 'Sorprendido'), 'enamorado': ('amor', 'Cariñoso'),
  'carinoso': ('amor', 'Cariñoso'), 'amor': ('amor', 'Cariñoso'),
  'pensando': ('pensando', 'Pensando'), 'piensa': ('pensando', 'Pensando'),
  'tranquilo': ('calma', 'Tranquilo'), 'tranquila': ('calma', 'Tranquilo'),
  'calma': ('calma', 'Tranquilo'), 'relajado': ('calma', 'Tranquilo'),
  'asustado': ('asustado', 'Asustado'), 'asustada': ('asustado', 'Asustado'),
};

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

RobotStep? _parseClause(String clause) {
  final w = _words(clause);
  if (w.isEmpty) return null;
  final n = w.join(' ');

  // Parar (máxima prioridad). "para" solo cuenta si no hay otra orden,
  // porque también es preposición ("ve para adelante").
  if (_hasAny(w, ['parate', 'detente', 'alto', 'quieto', 'quieta', 'stop', 'frena', 'detenerse', 'basta'])) {
    return const RobotStep('s', 'Parar', StepKind.stop);
  }

  // Comportamientos sociales
  if (_hasPrefix(w, ['bail'])) return const RobotStep('n', 'Bailar', StepKind.social);
  if (_hasAny(w, ['chiste', 'chistes', 'broma', 'bromas']) || _hasPhrase(n, ['algo gracioso'])) {
    return const RobotStep('j', 'Contar un chiste', StepKind.social);
  }
  if (_hasAny(w, ['piedra', 'tijera', 'tijeras']) || (_hasPrefix(w, ['jug', 'jueg']))) {
    return const RobotStep('x', 'Piedra, papel o tijera', StepKind.social);
  }
  if (_hasPrefix(w, ['respir', 'relaj']) || _hasPhrase(n, ['calmarnos', 'calmate'])) {
    return const RobotStep('e', 'Respirar juntos', StepKind.social);
  }
  if (_hasPrefix(w, ['celebr', 'felicit']) || _hasAny(w, ['bravo', 'logre', 'logramos', 'gane', 'ganamos'])) {
    return const RobotStep('c', 'Celebrar', StepKind.social);
  }
  if (_hasPrefix(w, ['despiert', 'despert', 'levantate'])) {
    return const RobotStep('w', 'Despertar', StepKind.social);
  }
  if (_hasPrefix(w, ['duerm', 'dormir', 'descans']) || _hasPhrase(n, ['buenas noches'])) {
    return const RobotStep('z', 'Dormir', StepKind.social);
  }
  if (_hasPrefix(w, ['salud', 'presentate']) || _hasAny(w, ['hola'])) {
    return const RobotStep('g', 'Saludar', StepKind.social);
  }

  // Garra
  if (_hasPrefix(w, ['agarr', 'atrap', 'recog']) || _hasAny(w, ['toma', 'coge', 'cierra', 'cerrar', 'agarra'])) {
    return const RobotStep('p', 'Agarrar', StepKind.claw);
  }
  if (_hasPrefix(w, ['suelt', 'solt']) || _hasAny(w, ['deja', 'dejalo', 'abre', 'abrir'])) {
    return const RobotStep('d', 'Soltar', StepKind.claw);
  }

  final q = _quantity(w);

  // Dar la vuelta
  if (_hasPhrase(n, ['media vuelta'])) return const RobotStep('t-180-g', 'Media vuelta', StepKind.turn);
  if (_hasAny(w, ['vuelta', 'vueltas', 'giro', 'gira', 'girar', 'voltea', 'voltear', 'dobla', 'doblar']) &&
      !_hasAny(w, ['izquierda', 'derecha'])) {
    if (q != null && q.unit == 'g') {
      return RobotStep('r-${_fmt(q.value)}-g', 'Girar ${_fmt(q.value)}°', StepKind.turn);
    }
    if (_hasAny(w, ['vuelta', 'vueltas'])) {
      final turns = (q != null && q.unit == null) ? q.value.clamp(1, 3) : 1;
      final deg = 360 * turns;
      return RobotStep('t-${_fmt(deg.toDouble())}-g', turns == 1 ? 'Dar una vuelta' : 'Dar ${_fmt(turns.toDouble())} vueltas', StepKind.turn);
    }
    return const RobotStep('r-90-g', 'Derecha 90°', StepKind.turn);
  }

  // Izquierda / derecha
  final left = w.contains('izquierda');
  final right = w.contains('derecha');
  if (left || right) {
    final code = left ? 'l' : 'r';
    final name = left ? 'Izquierda' : 'Derecha';
    if (q != null && q.unit == 's') {
      return RobotStep('$code-${_fmt(q.value)}-s', '$name ${_fmt(q.value)} s', StepKind.turn);
    }
    final deg = (q != null && (q.unit == 'g' || q.unit == null)) ? q.value.clamp(5, 720).toDouble() : 90.0;
    return RobotStep('$code-${_fmt(deg)}-g', '$name ${_fmt(deg)}°', StepKind.turn);
  }

  // Adelante / atrás
  final back = _hasAny(w, ['atras', 'retrocede', 'retroceder', 'retrocedes', 'regresa', 'regresar', 'reversa']);
  final fwd = _hasAny(w, ['adelante', 'avanza', 'avanzar', 'avanzas', 'sigue', 'recto', 'derecho', 'frente', 've', 'camina', 'caminar', 'muevete', 'anda', 'ven', 'acercate']) ||
      _hasPrefix(w, ['avanz', 'camin']);
  if (back || fwd) {
    final code = back ? 'b' : 'f';
    final name = back ? 'Atrás' : 'Adelante';
    var value = 20.0;
    var unit = 'cm';
    if (q != null) {
      switch (q.unit) {
        case 'm':
          value = q.value.clamp(0.05, 3).toDouble();
          unit = 'm';
        case 's':
          value = q.value.clamp(0.2, 10).toDouble();
          unit = 's';
        case 'paso':
          value = (q.value * 10).clamp(5, 300).toDouble();
        case 'g':
          break;
        default:
          value = q.value.clamp(1, 300).toDouble();
      }
    }
    final shown = unit == 'm' ? '${_fmt(value)} m' : unit == 's' ? '${_fmt(value)} s' : '${_fmt(value)} cm';
    return RobotStep('$code-${_fmt(value)}-$unit', '$name $shown', StepKind.move);
  }

  // Emociones ("ponte feliz", "estás triste")
  for (final word in w) {
    final e = _emotions[word];
    if (e != null) return RobotStep('m-${e.$1}', 'Cara: ${e.$2}', StepKind.emotion);
  }
  if (_hasAny(w, ['para', 'pare', 'paren'])) return const RobotStep('s', 'Parar', StepKind.stop);
  return null;
}

// --------------------------------------------------------------------------
// API pública

final _sayRegex = RegExp(r'(?:^|[\s,;.])(di|dile|dí|decir|repite|repetir)\s+(?:que\s+)?(.+)$', caseSensitive: false);
final _separators = RegExp(r'\s*(?:(?<!\d)[.,]|[.,](?!\d)|;|\by luego\b|\by despu[eé]s\b|\bluego\b|\bdespu[eé]s\b|\bentonces\b|\by\b)\s*', caseSensitive: false);

const _tens = {'veinte': 20, 'treinta': 30, 'cuarenta': 40, 'cincuenta': 50, 'sesenta': 60, 'setenta': 70, 'ochenta': 80, 'noventa': 90};
const _units = {'un': 1, 'uno': 1, 'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5, 'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9};

/// Une expresiones con "y" que NO separan órdenes: "treinta y cinco", "y medio".
String _preprocess(String s) {
  s = s.replaceAllMapped(
    RegExp(r'\b(veinte|treinta|cuarenta|cincuenta|sesenta|setenta|ochenta|noventa)\s+y\s+(uno|un|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)\b', caseSensitive: false),
    (m) => '${_tens[m.group(1)!.toLowerCase()]! + _units[m.group(2)!.toLowerCase()]!}',
  );
  return s.replaceAll(RegExp(r'\s+y\s+medi[oa]\b', caseSensitive: false), ' ymedio');
}

/// Interpreta una orden en español. Devuelve una lista vacía si no entiende nada.
ParsedCommand parseSpanishCommand(String text) {
  var input = text.trim();
  if (input.isEmpty) return const ParsedCommand([]);

  // "... y di hola a todos": lo que viene después de "di" se dice tal cual
  String? sayText;
  final say = _sayRegex.firstMatch(input);
  if (say != null && !_words(say.group(2)!).every((x) => x == 'un' || x == 'chiste')) {
    sayText = input.substring(say.start + say.group(0)!.indexOf(say.group(2)!)).trim();
    input = input.substring(0, say.start);
  }

  final steps = <RobotStep>[];
  for (final clause in _preprocess(input).split(_separators)) {
    final step = _parseClause(clause);
    if (step == null) continue;
    // evita duplicados seguidos ("baila, baila")
    if (steps.isNotEmpty && steps.last.code == step.code && step.kind != StepKind.move && step.kind != StepKind.turn) {
      continue;
    }
    steps.add(step);
  }

  if (sayText != null && sayText.isNotEmpty) {
    final clean = sayText.replaceAll(RegExp(r'[|;]'), ' ').trim();
    steps.add(RobotStep('h-$clean', 'Decir: "$clean"', StepKind.speak));
  }

  // "para" anula todo lo demás
  if (steps.any((s) => s.kind == StepKind.stop)) {
    return const ParsedCommand([RobotStep('s', 'Parar', StepKind.stop)]);
  }
  return ParsedCommand(steps);
}
