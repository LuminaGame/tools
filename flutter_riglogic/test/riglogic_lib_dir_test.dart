import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../hook/riglogic_lib_dir.dart';

/// Where the native-assets hook looks for the built OpenRigLogic library,
/// against real folders in the system temp directory.
void main() {
  const lib = 'riglogic.lib';
  late Directory temp;
  late Uri packageDefault;
  late Uri defined;

  String slash(String path) => path.replaceAll(r'\', '/');
  String dir(Uri uri) => slash(Directory.fromUri(uri).path).replaceAll(RegExp(r'/$'), '');
  void build(Uri folder) => File.fromUri(folder.resolve(lib)).createSync(recursive: true);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('riglogic_lib_dir_');
    packageDefault = Directory('${temp.path}/package/third_party/openriglogic/lib/').uri;
    defined = Directory('${temp.path}/app/openriglogic/lib/').uri;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  String resolve({String? environment, Uri? userDefine}) => resolveRiglogicLibDir(
        environment: environment,
        userDefine: userDefine,
        packageDefault: packageDefault,
        staticLib: lib,
      );

  test('a user-define that holds the library wins over the package build', () {
    build(packageDefault);
    build(defined);
    expect(resolve(userDefine: defined), dir(defined));
  });

  test('a user-define without the library yields to the package build', () {
    build(packageDefault);
    expect(resolve(userDefine: defined), dir(packageDefault));
  });

  test('with neither built, the user-define is reported', () {
    expect(resolve(userDefine: defined), dir(defined));
    expect(resolve(), dir(packageDefault));
  });

  test('the environment variable is taken as is', () {
    build(defined);
    final env = '${temp.path}${Platform.pathSeparator}elsewhere';
    expect(resolve(environment: env, userDefine: defined), slash(env));
    expect(resolve(environment: '', userDefine: defined), dir(defined));
  });

  test('a drive-letter user-define reads back as a Windows path', () {
    expect(riglogicDirPath(Uri.parse('D:/openriglogic/lib/')), 'D:/openriglogic/lib');
  });
}
