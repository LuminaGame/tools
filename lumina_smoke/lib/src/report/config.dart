import 'categories.dart';

/// A GPU backend the smoke targets run on, each run writing into its own
/// `<artifacts>/<name>/` folder.
class SmokeBackend {
  const SmokeBackend(this.name, {this.environment = const {}});

  /// The folder name and the report's backend tag (`opengl`, `vulkan`).
  final String name;

  /// Extra environment of this backend's runs (e.g. the variable that
  /// selects it).
  final Map<String, String> environment;
}

/// What a package's `tool/smoke_report.dart` tells the shared runner and
/// report generator.
class SmokeReportConfig {
  const SmokeReportConfig({
    required this.title,
    this.tag,
    this.dashboardTitle,
    this.categories = const TestCategories([]),
    this.categoryNote = 'One page per category; every PNG and video is linked from build/smoke_artifacts/, not embedded.',
    this.failingCategoriesFirst = false,
    this.orphanCategory,
    this.smokeDirs = const ['test/smoke'],
    this.extraSmokeTargets = const [],
    this.integrationDirs = const [],
    this.integrationSmokeDirs = const [],
    this.backends = const [],
    this.environment = const {},
    this.gpuName = 'RTX PRO 2000',
    this.cudaDevice = '1',
    this.gpuLabel = 'NVIDIA RTX PRO 2000 (GPU 1)',
    this.configDirVariable = 'LUMINA_CONFIG_DIR',
    this.scenarioKeywords = const [],
  });

  /// The report's title (`Lumina Engine Smoke & Test Report`).
  final String title;

  /// A short tag next to the title (`Core Engine`).
  final String? tag;

  /// The live dashboard's title; [title] when null.
  final String? dashboardTitle;

  /// How tests are grouped into pages.
  final TestCategories categories;

  /// The note above the index's category table.
  final String categoryNote;

  /// Whether categories with failures come first in the index and the page
  /// navigation (else the [categories] order alone).
  final bool failingCategoriesFirst;

  /// When set, every artifact that matches no test goes on this one page;
  /// otherwise each goes to the category its name (and file) falls in.
  final String? orphanCategory;

  /// The folders (relative to the package) whose tests are smoke tests: run
  /// one file at a time (`--concurrency=1`), after the unit tests, on every
  /// backend. The default run (no targets) runs these.
  final List<String> smokeDirs;

  /// Further smoke files or folders, run with the smoke tests when they
  /// exist.
  final List<String> extraSmokeTargets;

  /// Integration-test folders (`integration_test`): their files run one by
  /// one on the host's desktop device.
  final List<String> integrationDirs;

  /// The smoke folders among [integrationDirs] (`integration_test/smoke`),
  /// run by the default smoke run.
  final List<String> integrationSmokeDirs;

  /// GPU backends. Empty: one run, artifacts straight into the artifact
  /// directory. Otherwise the first backend runs every target and the others
  /// the smoke targets, each into `<artifacts>/<backend>/`.
  final List<SmokeBackend> backends;

  /// Extra environment of every run.
  final Map<String, String> environment;

  /// The GPU every run is pinned to, by name (`FILAMENT_GPU`): under PRIME
  /// offload the Vulkan device order changes, so an index would pick another
  /// card.
  final String gpuName;

  /// `CUDA_VISIBLE_DEVICES` of every run.
  final String cudaDevice;

  /// The GPU as the report names it.
  final String gpuLabel;

  /// When set, every run gets this variable pointing at a throwaway
  /// directory, so the tests' editor configuration (recent projects,
  /// settings) never touches the user's own.
  final String? configDirVariable;

  /// Module words that tie a `Scenario NN` artifact to the `Scenario NN` test
  /// of the same module when the names differ otherwise (e.g. `static_mesh`,
  /// `camera`): both the artifact name and the test name or file must
  /// contain one.
  final List<String> scenarioKeywords;

  /// The category of the test [name] in the file [suite].
  String categoryOf(String suite, String name) => categories.categoryOf(suite, name);

  /// Where [category] goes in the report.
  int categoryOrder(String category) => categories.orderOf(category);
}
