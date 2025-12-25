
import 'storage_usage_service.dart';

/// Web implementation of StorageUsageService (Stub)
class StorageUsageService {
  StorageUsageService._();

  static Future<StorageUsageReport> computeReport() async => generateReport();

  static Future<StorageUsageReport> generateReport() async {
    // Return empty report
    return const StorageUsageReport(
      totalBytes: 0,
      totalFiles: 0,
      clearable: StorageUsageStats(fileCount: 0, bytes: 0),
      categories: [],
    );
  }

  static Future<void> clearCache({bool avatarsOnly = false}) async {}

  static Future<void> clearOtherCache() async {}

  static Future<void> clearLogs() async {}
  
  static Future<void> clearSystemCache() async {}

  static Future<List<StorageFileEntry>> listLogEntries() async => [];

  static Future<int> deleteLogFiles(Iterable<String> paths) async => 0;

  static Future<List<StorageFileEntry>> listAvatarEntries() async => [];
  
  static Future<List<StorageFileEntry>> listUploadEntries({bool images = false}) async => [];
  
  static Future<int> deleteUploadFiles(Iterable<String> paths, {bool images = false}) async => 0;

  static Future<int> deleteAvatarFiles(Iterable<String> paths) async => 0;

  static Future<void> clearAvatars() async {}

  static Future<List<StorageFileEntry>> listCacheEntries() async => [];

  static Future<List<StorageFileEntry>> listChatDataEntries() async => [];
}
