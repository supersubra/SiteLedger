import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:siteledger/ledger.dart';

void main() {
  test(
    'reopened queue retains receipt and UUID until matching acknowledgment',
    () async {
      sqfliteFfiInit();
      final folder = await Directory.systemTemp.createTemp('ledger-test');
      addTearDown(() => folder.delete(recursive: true));
      final path = '${folder.path}/claims.sqlite';
      Future<Outbox> open() async => Outbox(
        await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) => db.execute(
              'CREATE TABLE queue(id TEXT PRIMARY KEY,owner TEXT NOT NULL,payload TEXT NOT NULL)',
            ),
          ),
        ),
      );
      var box = await open();
      final payload = {'client_id': 'example', 'receipt': 'example bytes'};
      await box.save('tech', payload);
      await box.db.close();
      box = await open();
      expect(await box.pending('other'), isEmpty);
      await expectLater(
        box.sync(
          'tech',
          (item) async => throw const SocketException('lost acknowledgment'),
        ),
        throwsA(isA<SocketException>()),
      );
      expect(await box.pending('tech'), [payload]);
      await box.sync(
        'tech',
        (item) async => {'client_id': item['client_id'], 'number': 'EXP-0001'},
      );
      expect(await box.pending('tech'), isEmpty);
      await box.db.close();
    },
  );
}
