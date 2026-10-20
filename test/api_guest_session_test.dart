import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';

class _Storage extends SecureStorageService {
  String? token;
  int clears = 0;
  int refreshReads = 0;
  @override
  Future<String?> get accessToken async => token;
  @override
  Future<String?> get refreshToken async {
    refreshReads++;
    return null;
  }

  @override
  Future<void> clear() async {
    token = null;
    clears++;
  }
}

class _Unauthorized implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"title":"Authentication required"}', 401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

void main() {
  AppEnvironment.configure(baseUrl: 'https://example.invalid/api');
  for (final authenticated in [false, true]) {
    test('401 expires only an authenticated session: $authenticated', () async {
      final storage = _Storage()..token = authenticated ? 'test-token' : null;
      final client = await ApiClient(storage).init();
      client.dio.httpClientAdapter = _Unauthorized();
      addTearDown(() => client.dio.close(force: true));
      var expirations = 0;
      client.onSessionExpired = () async => expirations++;
      for (var request = 0; request < 3; request++) {
        final result = await client.execute<Object?>(
            model: 'SavedPlaceModel', operation: 'list');
        expect(result, isA<ApiFailure<Object?>>());
      }
      expect(expirations, authenticated ? 1 : 0);
      expect(storage.clears, authenticated ? 1 : 0);
      expect(storage.refreshReads, authenticated ? 1 : 0);
    });
  }
}
