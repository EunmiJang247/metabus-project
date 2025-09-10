import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ArCoreExample());
  }
}

class ArCoreExample extends StatefulWidget {
  const ArCoreExample({super.key});

  @override
  State<ArCoreExample> createState() => _ArCoreExampleState();
}

class _ArCoreExampleState extends State<ArCoreExample> {
  ArCoreController? arCoreController;

  @override
  void dispose() {
    arCoreController?.dispose();
    super.dispose();
  }

  void _onArCoreViewCreated(ArCoreController controller) {
    arCoreController = controller;
    _addSphere(controller);
  }

  void _addSphere(ArCoreController controller) {
    final material = ArCoreMaterial(color: Colors.red, metallic: 1.0);

    final sphere = ArCoreSphere(materials: [material], radius: 0.1);

    final node = ArCoreNode(
      shape: sphere,
      position: vector.Vector3(0, 0, -1), // 카메라 앞 1m 위치
    );

    controller.addArCoreNode(node);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ARCore Sample")),
      body: ArCoreView(
        onArCoreViewCreated: _onArCoreViewCreated,
        enableTapRecognizer: true,
      ),
    );
  }
}
