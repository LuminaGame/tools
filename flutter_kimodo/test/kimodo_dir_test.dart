import 'package:flutter_test/flutter_test.dart';

import '../hook/kimodo_dir.dart';

void main() {
  const lib = 'bin/kimodo.dll';
  final packageDefault = Uri.parse(
    'file:///D:/lumina/tools/flutter_kimodo/third_party/kimodo/prebuilt/v/windows-x64/',
  );
  const defaultDir =
      'D:/lumina/tools/flutter_kimodo/third_party/kimodo/prebuilt/v/windows-x64';

  test('the environment wins as is', () {
    expect(
      resolveKimodoDir(
        environment: r'E:\kimodo\',
        packageDefault: packageDefault,
        library: lib,
        exists: (_) => false,
      ),
      'E:/kimodo',
    );
  });

  test('a user-define holding the library wins over the package build', () {
    expect(
      resolveKimodoDir(
        userDefine: Uri.parse('E:/prebuilt/'),
        packageDefault: packageDefault,
        library: lib,
        exists: (path) => true,
      ),
      'E:/prebuilt',
    );
  });

  test('an empty user-define yields to the package build when it has one', () {
    expect(
      resolveKimodoDir(
        userDefine: Uri.parse('E:/prebuilt/'),
        packageDefault: packageDefault,
        library: lib,
        exists: (path) => path.startsWith(defaultDir),
      ),
      defaultDir,
    );
    // Neither holds it: the user-define is named in the error.
    expect(
      resolveKimodoDir(
        userDefine: Uri.parse('E:/prebuilt/'),
        packageDefault: packageDefault,
        library: lib,
        exists: (_) => false,
      ),
      'E:/prebuilt',
    );
  });

  test('libraries per platform', () {
    expect(kimodoLibrary('windows'), 'bin/kimodo.dll');
    expect(kimodoLibrary('linux'), 'lib/libkimodo.so');
    expect(kimodoPlatform('windows', 'x64'), 'windows-x64');
  });
}
