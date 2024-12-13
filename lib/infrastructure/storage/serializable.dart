import "package:ev3_client/infrastructure/storage/file_manager.dart";
import "package:logging/logging.dart";

final _log = Logger("Serializable");

abstract class Serializable<T> {
  Map<String, dynamic> toJson();
  String filename();

  Future<void> save({bool createDir = false}) async {
    await saveObject(this, filename(), mkdirs: createDir);
  }

  static Future<Map<String, dynamic>> loadData<T extends Serializable>(String filename) async {
    return await readObject(filename);
  }

  static Future<bool> fileExists(String filename) => exists(filename);

  static Future<List<String>> debug() => listFiles();
}