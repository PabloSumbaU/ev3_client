import 'dart:io';

import 'package:ev3_client/presentation/control_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../infrastructure/gemini.dart';
import '../infrastructure/socket_connection.dart';

final log = Logger("Connect Page");
final ipRegex = RegExp("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\$");

Future<File> _ipFile() async => File('${(await getApplicationDocumentsDirectory()).path}/last_ip.txt');

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadLastIp();
  }

  Future<void> _loadLastIp() async {
    try {
      final f = await _ipFile();
      if (await f.exists()) {
        final ip = (await f.readAsString()).trim();
        if (mounted && _controller.text.isEmpty) _controller.text = ip;
      }
    } catch (e) {
      log.fine("No hay IP guardada: $e");
    }
  }

  Future<void> _saveIp(String ip) async {
    try {
      await (await _ipFile()).writeAsString(ip);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onConnect() async {
    if (_connecting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _connecting = true);

    final ip = _controller.text.trim();
    await connect(ip);
    if (!mounted) return;
    setState(() => _connecting = false);

    final messenger = ScaffoldMessenger.of(context);
    if (isConnected()) {
      _saveIp(ip);
      messenger.showSnackBar(const SnackBar(content: Text("Conexión establecida")));
      await Navigator.push(context, MaterialPageRoute(builder: (context) => const ControlPage()));
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      messenger.showSnackBar(const SnackBar(
        content: Text("No se pudo conectar. ¿El robot muestra \"Esperando la app\" y la misma IP?"),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(Icons.smart_toy_rounded, size: 52, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 16),
                    Text("Robot social EV3", textAlign: TextAlign.center, style: text.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      "Escribe la IP que aparece en la pantalla del robot",
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _controller,
                      enabled: !_connecting,
                      decoration: const InputDecoration(
                        labelText: "IP del robot",
                        hintText: "192.168.44.xx",
                        prefixIcon: Icon(Icons.wifi_tethering_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.go,
                      onFieldSubmitted: (_) => _onConnect(),
                      validator: (ip) => ipRegex.hasMatch(ip?.trim() ?? "") ? null : "IP inválida",
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _connecting ? null : _onConnect,
                      icon: _connecting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Icon(Icons.link_rounded),
                      label: Text(_connecting ? "Conectando..." : "Conectar"),
                    ),
                    const SizedBox(height: 16),
                    const ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text("¿Cómo conectar?"),
                      childrenPadding: EdgeInsets.only(bottom: 8),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("1. Activa el punto de acceso por Bluetooth del teléfono."),
                        Text("2. En el robot: Wireless and Networks > Bluetooth > conecta el teléfono."),
                        Text("3. Ejecuta main.py en el robot."),
                        Text("4. Cuando muestre \"Esperando la app\", escribe aquí su IP."),
                      ],
                    ),
                    Text(
                      Gemini.isConfigured
                          ? "Voz con IA: ${Gemini.modelName}"
                          : "Voz: intérprete local (sin clave de Gemini)",
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
