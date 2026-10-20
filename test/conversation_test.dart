import 'package:ev3_client/infrastructure/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JSON normal', () {
    final r = parseReply('{"decir": "¡Hola! Soy Lumi.", "emocion": "feliz", "accion": "ninguna"}');
    expect(r.say, '¡Hola! Soy Lumi.');
    expect(r.emotion, 'feliz');
    expect(r.action, isNull);
  });
  test('acción y limpieza de emojis/asteriscos', () {
    final r = parseReply('```json\n{"decir": "**¡Bailemos!** 💃", "emocion": "amor", "accion": "bailar"}\n```');
    expect(r.say, '¡Bailemos!');
    expect(r.emotion, 'amor');
    expect(r.action, 'n');
  });
  test('emoción desconocida y texto sin JSON', () {
    expect(parseReply('{"decir": "ok", "emocion": "furioso"}').emotion, 'feliz');
    expect(parseReply('Hola amigo').say, 'Hola amigo');
  });
}
