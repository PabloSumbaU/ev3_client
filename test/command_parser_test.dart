import 'package:ev3_client/infrastructure/command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String p(String s) => parseSpanishCommand(s).instructions;

void main() {
  final cases = <String, String>{
    'avanza': 'f-20-cm',
    'adelante 30 centímetros': 'f-30-cm',
    'avanza 1.5 metros': 'f-1.5-m',
    'avanza un metro y medio': 'f-1.5-m',
    'avanza treinta y cinco centímetros': 'f-35-cm',
    'retrocede dos segundos': 'b-2-s',
    've hacia atrás 20cm': 'b-20-cm',
    'gira a la derecha': 'r-90-g',
    'gira 45 grados a la izquierda': 'l-45-g',
    'izquierda': 'l-90-g',
    'da una vuelta': 't-360-g',
    'da media vuelta': 't-180-g',
    'avanza 20 centímetros, gira a la izquierda y luego agarra': 'f-20-cm;l-90-g;p',
    'suelta la pelota': 'd',
    'agarra el objeto y retrocede': 'p;b-20-cm',
    'para': 's',
    'detente ya': 's',
    'avanza y después para': 's',
    've para adelante': 'f-20-cm',
    'baila': 'n',
    'hola lumi': 'g',
    'saluda a mi amigo': 'g',
    'cuéntame un chiste': 'j',
    'dime un chiste': 'j',
    'vamos a respirar juntos': 'e',
    'juguemos piedra papel o tijera': 'x',
    'celebra': 'c',
    'a dormir': 'z',
    'despierta': 'w',
    'ponte feliz': 'm-feliz',
    'estás triste': 'm-triste',
    'saluda y di que hoy es un gran día': 'g;h-hoy es un gran día',
    'di Hola María': 'h-Hola María',
    'blablabla': '',
  };
  cases.forEach((input, expected) {
    test('"$input" -> "$expected"', () => expect(p(input), expected));
  });

  test('respuesta tipo Gemini', () {
    expect(p('adelante 10 cm, izquierda 90 grados, saluda, di Aquí estoy contigo'),
        'f-10-cm;l-90-g;g;h-Aquí estoy contigo');
    expect(p('atrás 2 segundos, ponte tranquilo'), 'b-2-s;m-calma');
  });
}
