import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riglogic/flutter_riglogic.dart';

void main() {
  runApp(const RigLogicExampleApp());
}

class RigLogicExampleApp extends StatelessWidget {
  const RigLogicExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina RigLogic Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF121214),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E1E24),
        ),
      ),
      home: const RigLogicDashboard(),
    );
  }
}

class RigLogicDashboard extends StatefulWidget {
  const RigLogicDashboard({super.key});

  @override
  State<RigLogicDashboard> createState() => _RigLogicDashboardState();
}

class _RigLogicDashboardState extends State<RigLogicDashboard> {
  DnaReader? _dnaReader;
  RigLogic? _rigLogic;
  RigInstance? _rigInstance;

  bool _isLoading = true;
  String? _errorMessage;

  final Map<int, double> _controlValues = {};
  List<double> _blendShapeOutputs = [];
  List<double> _jointOutputs = [];
  List<double> _animatedMapOutputs = [];

  @override
  void initState() {
    super.initState();
    _loadDnaAndInitialize();
  }

  Future<void> _loadDnaAndInitialize() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final byteData = await rootBundle.load('assets/sample.dna');
      final bytes = byteData.buffer.asUint8List();

      final reader = DnaReader.fromMemory(bytes);
      final rigLogic = RigLogic.create(reader);
      final instance = RigInstance.create(rigLogic);

      for (int i = 0; i < reader.rawControlCount; i++) {
        _controlValues[i] = 0.0;
        instance.setRawControl(i, 0.0);
      }

      rigLogic.calculate(instance);

      setState(() {
        _dnaReader = reader;
        _rigLogic = rigLogic;
        _rigInstance = instance;
        _blendShapeOutputs = instance.getBlendShapeOutputs();
        _jointOutputs = instance.getJointOutputs();
        _animatedMapOutputs = instance.getAnimatedMapOutputs();
        _isLoading = false;
      });
    } catch (e, stack) {
      setState(() {
        _errorMessage = 'Failed to load OpenRigLogic DNA: $e\n$stack';
        _isLoading = false;
      });
    }
  }

  void _onControlChanged(int index, double value) {
    final instance = _rigInstance;
    final rigLogic = _rigLogic;
    if (instance == null || rigLogic == null) return;

    setState(() {
      _controlValues[index] = value;
      instance.setRawControl(index, value);
      rigLogic.calculate(instance);
      _blendShapeOutputs = instance.getBlendShapeOutputs();
      _jointOutputs = instance.getJointOutputs();
      _animatedMapOutputs = instance.getAnimatedMapOutputs();
    });
  }

  void _resetAllControls() {
    final instance = _rigInstance;
    final rigLogic = _rigLogic;
    final reader = _dnaReader;
    if (instance == null || rigLogic == null || reader == null) return;

    setState(() {
      for (int i = 0; i < reader.rawControlCount; i++) {
        _controlValues[i] = 0.0;
        instance.setRawControl(i, 0.0);
      }
      rigLogic.calculate(instance);
      _blendShapeOutputs = instance.getBlendShapeOutputs();
      _jointOutputs = instance.getJointOutputs();
      _animatedMapOutputs = instance.getAnimatedMapOutputs();
    });
  }

  @override
  void dispose() {
    _rigInstance?.dispose();
    _rigLogic?.dispose();
    _dnaReader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.face_retouching_natural, color: Color(0xFF3B82F6)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Lumina RigLogic — Realtime MetaHuman Evaluator',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E24),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset All Controls',
            onPressed: _resetAllControls,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing OpenRigLogic runtime...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadDnaAndInitialize,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final reader = _dnaReader!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final leftPane = Container(
          color: const Color(0xFF18181C),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildMetadataCard(reader),
              const SizedBox(height: 16),
              _buildControlInputsCard(reader),
            ],
          ),
        );

        final rightPane = Container(
          color: const Color(0xFF121214),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildBlendShapesCard(reader),
              const SizedBox(height: 16),
              _buildJointOutputsCard(reader),
              const SizedBox(height: 16),
              _buildAnimatedMapsCard(reader),
            ],
          ),
        );

        if (isNarrow) {
          return Column(
            children: [
              Expanded(child: leftPane),
              const Divider(height: 1, color: Color(0xFF2E2E36)),
              Expanded(child: rightPane),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 5, child: leftPane),
            const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF2E2E36)),
            Expanded(flex: 6, child: rightPane),
          ],
        );
      },
    );
  }

  Widget _buildMetadataCard(DnaReader reader) {
    return Card(
      color: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Color(0xFF3B82F6)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'DNA METADATA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E2E36), height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildMetaItem('Character', reader.name),
                _buildMetaItem('LODs', '${reader.lodCount}'),
                _buildMetaItem('Joints', '${reader.jointCount}'),
                _buildMetaItem('BlendShapes', '${reader.blendShapeChannelCount}'),
                _buildMetaItem('Raw Controls', '${reader.rawControlCount}'),
                _buildMetaItem('Animated Maps', '${reader.animatedMapCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildControlInputsCard(DnaReader reader) {
    return Card(
      color: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 18, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'INPUT CONTROLS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetAllControls,
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E2E36), height: 16),
            for (int i = 0; i < reader.rawControlCount; i++)
              _buildControlSlider(i, reader.getRawControlName(i)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlSlider(int index, String name) {
    final value = _controlValues[index] ?? 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$name (Control $index)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: (val) => _onControlChanged(index, val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlendShapesCard(DnaReader reader) {
    return Card(
      color: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: Color(0xFFF59E0B)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CALCULATED BLEND SHAPES (MORPH TARGETS)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E2E36), height: 16),
            for (int i = 0; i < _blendShapeOutputs.length; i++)
              _buildOutputMeter(
                reader.getBlendShapeChannelName(i),
                _blendShapeOutputs[i],
                const Color(0xFFF59E0B),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJointOutputsCard(DnaReader reader) {
    return Card(
      color: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hub, size: 18, color: Color(0xFF8B5CF6)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CALCULATED JOINT DELTAS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E2E36), height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < reader.jointCount; i++)
                  _buildJointDeltaSummary(i, reader.getJointName(i)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJointDeltaSummary(int jointIndex, String name) {
    // 9 floats per joint (3 translation, 3 rotation, 3 scale)
    final offset = jointIndex * 9;
    if (offset + 8 >= _jointOutputs.length) return const SizedBox.shrink();

    final tx = _jointOutputs[offset + 0];
    final ty = _jointOutputs[offset + 1];
    final tz = _jointOutputs[offset + 2];
    final rx = _jointOutputs[offset + 3];
    final ry = _jointOutputs[offset + 4];
    final rz = _jointOutputs[offset + 5];

    final hasDelta = tx.abs() > 0.001 || ty.abs() > 0.001 || tz.abs() > 0.001 ||
        rx.abs() > 0.001 || ry.abs() > 0.001 || rz.abs() > 0.001;

    return Container(
      width: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasDelta ? const Color(0xFF8B5CF6) : const Color(0xFF282830),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: hasDelta ? const Color(0xFFA78BFA) : Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'T: (${tx.toStringAsFixed(2)}, ${ty.toStringAsFixed(2)}, ${tz.toStringAsFixed(2)})',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
          ),
          Text(
            'R: (${rx.toStringAsFixed(2)}, ${ry.toStringAsFixed(2)}, ${rz.toStringAsFixed(2)})',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedMapsCard(DnaReader reader) {
    return Card(
      color: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.animation, size: 18, color: Color(0xFF06B6D4)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ANIMATED MAP OUTPUTS (WRINKLE MAP WEIGHTS)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E2E36), height: 16),
            for (int i = 0; i < _animatedMapOutputs.length; i++)
              _buildOutputMeter(
                reader.getAnimatedMapName(i),
                _animatedMapOutputs[i],
                const Color(0xFF06B6D4),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputMeter(String name, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value.toStringAsFixed(3),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFF282830),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
