import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef Json = Map<String, dynamic>;
const project = 'CityCare Block A electrification';
const building = 'Block A';

class LedgerApi {
  LedgerApi(this.base);
  final Uri base;
  String token = '';
  Future<dynamic> request(String path, [Json? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        body == null ? 'GET' : 'POST',
        base.resolve('/v1/$path'),
      );
      if (token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final data = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 15)),
      );
      if (response.statusCode >= 400) {
        throw Exception(
          data['detail'] is String
              ? data['detail']
              : 'Invalid field or attachment',
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }
}

class Outbox {
  Outbox(this.db);
  final Database db;
  static Future<Outbox> open() async {
    final dir = await getApplicationSupportDirectory();
    final factory = Platform.isWindows ? databaseFactoryFfi : databaseFactory;
    if (Platform.isWindows) sqfliteFfiInit();
    final db = await factory.openDatabase(
      '${dir.path}/claims.sqlite',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE queue (id TEXT PRIMARY KEY, owner TEXT NOT NULL, payload TEXT NOT NULL)',
          );
        },
      ),
    );
    return Outbox(db);
  }

  Future<void> save(String owner, Json data) async {
    await db.insert('queue', {
      'id': data['client_id'],
      'owner': owner,
      'payload': jsonEncode(data),
    });
  }

  Future<List<Json>> pending(String owner) async {
    final rows = await db.query(
      'queue',
      where: 'owner = ?',
      whereArgs: [owner],
      orderBy: 'rowid',
    );
    return [
      for (final row in rows) jsonDecode(row['payload'] as String) as Json,
    ];
  }

  Future<void> sync(String owner, Future<dynamic> Function(Json) submit) async {
    for (final data in await pending(owner)) {
      final ack = await submit(data);
      if (ack['client_id'] != data['client_id'] || ack['number'] == null) {
        throw Exception('Missing claim acknowledgment');
      }
      await db.delete(
        'queue',
        where: 'owner = ? AND id = ?',
        whereArgs: [owner, data['client_id']],
      );
    }
  }
}
