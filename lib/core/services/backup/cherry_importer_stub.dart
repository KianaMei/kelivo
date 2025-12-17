import '../../models/backup.dart';
import '../../providers/settings_provider.dart';
import '../chat/chat_service.dart';

/// Web stub - Cherry Studio import not supported on web
class CherryImporter {
  static Future<void> importFromCherryStudio({
    required dynamic file,
    required RestoreMode mode,
    required SettingsProvider settings,
    required ChatService chatService,
  }) async {
    throw UnsupportedError('Cherry Studio import not supported on web');
  }
}
