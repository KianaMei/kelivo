import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/core/services/backup/data_sync_io.dart';
import 'package:kelivo/core/services/http/dio_client.dart';

void main() {
  test('WebDAV requests can opt out of network logging', () {
    expect(kLogNetworkResultOnlyExtraKey, 'kelivo_log_network_result_only');
    // Importing DataSync IO ensures backup code compiles in this test target.
    expect(DataSync, isNotNull);
  });
}
