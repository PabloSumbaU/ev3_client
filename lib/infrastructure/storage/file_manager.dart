import 'dart:convert';

import 'package:ev3_client/infrastructure/storage/serializable.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

final _log = Logger("File Manager");

Future<String> get _localPath async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

Future<List<String>> listFiles() async {
  _log.warning("Function listFiles intended for debug purposes only was called. Remove later!");
  final path = await _localPath;
  return Directory(path).list().map((file) => file.path).toList();
}

Future<File> getFile(String filename) async {
  final path = await _localPath;
  return File('$path/$filename');
}

Future<bool> exists(String filename) async {
  final path = await _localPath;
  return File('$path/$filename').exists();
}

Future<void> saveObject<T extends Serializable>(T object, String filename, {bool mkdirs = false}) async {
  final file = await getFile(filename);

  if (mkdirs) {
    file.parent.create(recursive: true);
  }

  await file.writeAsString(jsonEncode(object));
}

Future<Map<String, dynamic>> readObject(String filename) async {
  final file = await getFile(filename);

  return jsonDecode(await file.readAsString());
}