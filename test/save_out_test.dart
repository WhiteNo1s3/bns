/// A BACKUP MUST BE FINDABLE (owner QA, 2026-08-15: "I couldn't save on
/// android... where did it save the file? on android its broken").
///
/// The export was written into app-private internal storage, so the app
/// told the truth about the file's name and nothing useful about its
/// place. These tests cover the small, pure part of the fix: naming the
/// folder a person should open, across both path styles, since a .bns
/// travels between a Windows PC and a phone.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/data/export/bns_save_out.dart';

void main() {
  test('the folder is named, not just the file', () {
    expect(
      BnsSaveOut.folderOf('/Users/ben/Documents/bns/exports/BNS_Backup.bns'),
      '/Users/ben/Documents/bns/exports',
    );
    expect(
      BnsSaveOut.folderOf(r'C:\Users\Shaltiel\Documents\bns\exports\BNS.bns'),
      r'C:\Users\Shaltiel\Documents\bns\exports',
    );
  });

  test('the file name survives either separator (paths cross machines)', () {
    expect(BnsSaveOut.fileNameOf('/storage/emulated/0/Download/BNS.bns'),
        'BNS.bns');
    expect(BnsSaveOut.fileNameOf(r'D:\backups\BNS_Backup_PC.bns'),
        'BNS_Backup_PC.bns');
    // A trailing separator must not yield an empty name.
    expect(BnsSaveOut.fileNameOf('/tmp/exports/'), 'exports');
  });

  test('a bare name is its own file, with no folder invented for it', () {
    expect(BnsSaveOut.fileNameOf('BNS.bns'), 'BNS.bns');
    expect(BnsSaveOut.folderOf('BNS.bns'), 'BNS.bns');
  });
}
