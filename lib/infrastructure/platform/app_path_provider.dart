import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Abstract path provider contract for platform-independent storage resolution.
abstract class IAppPathProvider {
  Future<String> getDatabaseDirectory();
  Future<String> getBackupsDirectory();
  Future<String> getMediaDirectory();
  Future<String> getExportsDirectory();
}

/// Production implementation of [IAppPathProvider].
class ProductionAppPathProvider implements IAppPathProvider {
  @override
  Future<String> getDatabaseDirectory() async {
    final base = await _getBaseDirectory();
    final dbDir = Directory(p.join(base, 'data'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    return dbDir.path;
  }

  @override
  Future<String> getBackupsDirectory() async {
    final base = await _getBaseDirectory();
    final backupDir = Directory(p.join(base, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir.path;
  }

  @override
  Future<String> getMediaDirectory() async {
    final base = await _getBaseDirectory();
    final mediaDir = Directory(p.join(base, 'media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir.path;
  }

  @override
  Future<String> getExportsDirectory() async {
    if (Platform.isWindows) {
      final docs = await getApplicationDocumentsDirectory();
      final exportDir = Directory(p.join(docs.path, 'Billzo', 'exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      return exportDir.path;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    }
  }

  Future<String> _getBaseDirectory() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'Billzo');
      }
    }
    final appDocDir = await getApplicationSupportDirectory();
    return appDocDir.path;
  }
}
