import 'package:ev3_client/presentation/control_page.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter/services.dart';

import '../infrastructure/socket_connection.dart';

final log = Logger("Connect Page");
final ipRegex = RegExp("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\$");

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: IPForm(),
      ),
    );
  }
}

class IPForm extends StatefulWidget {
  const IPForm({super.key});

  @override
  State<StatefulWidget> createState() {
    return IPFormState();
  }
  
}

class IPFormState extends State<IPForm> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _failedConnection = const SnackBar(content: Text("Conexión fallida"));
  final _successfulConnection = const SnackBar(content: Text("Conexión establecida"));

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "IP del robot",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: _ipValidate,
            ),
            ElevatedButton(
              onPressed: _onPressed, 
              child: const Text("Conectar")
            ),
          ],
        ),
      ),
    );
  }

  String? _ipValidate(String? ip) {
    return ipRegex.hasMatch(ip??"") ? null : "IP inválida";
  }

  void _onPressed() {
    if (_formKey.currentState!.validate()) {
      _onConnecting().then((value){
        if (isConnected()) {
          ScaffoldMessenger.of(context).showSnackBar(_successfulConnection);
          Navigator.push(
            context, 
            MaterialPageRoute(builder: (context) => ControlPage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(_failedConnection);
        }
      });
    }
  }

  Future<void> _onConnecting() async {
    showDialog(context: context,
      builder: (context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(4.0),
            child: Row(
              mainAxisAlignment:MainAxisAlignment.spaceAround,
              children: [
                CircularProgressIndicator(),
                Text("Conectando..."),
              ],
            ),
          ),
        );
      }
    );

    await connect(_controller.text);

    if(mounted) Navigator.pop(context);
  }
}