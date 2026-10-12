import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_jolt/src/hook/jolt_dir.dart';

/// Where the native-assets hook looks for the Jolt build, against real
/// folders in the system temp directory, and the defines file it reads.
void main() {
  const lib = 'Jolt.lib';
  late Directory temp;
  late Uri packageDefault;
  late Uri defined;

  String slash(String path) => path.replaceAll(r'\', '/');
  String dir(Uri uri) =>
      slash(Directory.fromUri(uri).path).replaceAll(RegExp(r'/$'), '');
  void build(Uri folder) =>
      File.fromUri(folder.resolve('lib/$lib')).createSync(recursive: true);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jolt_dir_');
    packageDefault = Directory('${temp.path}/package/third_party/jolt/').uri;
    defined = Directory('${temp.path}/app/jolt/').uri;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  String resolve({String? environment, Uri? userDefine}) => resolveJoltDir(
    environment: environment,
    userDefine: userDefine,
    packageDefault: packageDefault,
    staticLib: lib,
  );

  test('the environment variable wins', () {
    expect(
      resolve(environment: '${temp.path}/env', userDefine: defined),
      slash('${temp.path}/env'),
    );
  });

  test('a user-define holding the library wins over the package build', () {
    build(defined);
    build(packageDefault);
    expect(resolve(userDefine: defined), dir(defined));
  });

  test(
    'an empty user-define yields to a package build, but names the folder when neither has one',
    () {
      build(packageDefault);
      expect(resolve(userDefine: defined), dir(packageDefault));
      File.fromUri(packageDefault.resolve('lib/$lib')).deleteSync();
      expect(resolve(userDefine: defined), dir(defined));
    },
  );

  test('without a user-define the package build is used', () {
    expect(resolve(), dir(packageDefault));
  });

  test('defines: names, values, comments and blank lines', () {
    expect(
      parseJoltDefines(
        'JPH_OBJECT_LAYER_BITS=16\n\n# comment\nJPH_USE_SSE4_1\r\n',
      ),
      {'JPH_OBJECT_LAYER_BITS': '16', 'JPH_USE_SSE4_1': null},
    );
  });
}
