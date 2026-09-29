import 'dart:async';
import 'dart:io';

/// Child processes of the report runner that can never outlive it: on Linux
/// every `flutter test` run leads its own process group (via `setsid`), and
/// the groups are killed on SIGINT / SIGTERM and before the runner exits, so
/// no `flutter_tester` is left behind even after the flutter tool itself has
/// exited. Elsewhere the child is started normally (`flutter` is a `.bat` on
/// Windows, found only through the shell).
abstract final class SmokeProcessGroups {
  static final Set<int> _groups = <int>{};
  static bool _watching = false;

  /// Starts [executable] with [arguments], leading its own process group on
  /// Linux (`setsid` execs in place, so the pid is the group id).
  static Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    if (!Platform.isLinux) {
      return Process.start(executable, arguments,
          environment: environment, workingDirectory: workingDirectory, runInShell: Platform.isWindows);
    }
    final process = await Process.start('setsid', [executable, ...arguments],
        environment: environment, workingDirectory: workingDirectory);
    _groups.add(process.pid);
    return process;
  }

  /// Sends [signal] to every child group; a group that is already gone is
  /// ignored.
  static void signalAll(ProcessSignal signal) {
    for (final group in _groups) {
      try {
        Process.runSync('kill', ['-${signal.name.substring(3)}', '--', '-$group']);
      } catch (_) {}
    }
  }

  /// On SIGINT / SIGTERM, terminates the child groups (SIGKILL after a grace
  /// period) and exits. Linux only; a no-op elsewhere.
  static void killChildrenOnSignals() {
    if (!Platform.isLinux || _watching) return;
    _watching = true;
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signal.watch().listen((_) async {
        signalAll(ProcessSignal.sigterm);
        await Future<void>.delayed(const Duration(seconds: 2));
        exitKillingChildren(signal == ProcessSignal.sigint ? 130 : 143);
      });
    }
  }

  /// Kills whatever is still in a child group (an orphan of a finished run)
  /// and exits with [code].
  static Never exitKillingChildren(int code) {
    if (Platform.isLinux) signalAll(ProcessSignal.sigkill);
    exit(code);
  }
}
