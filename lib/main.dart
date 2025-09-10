import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() => runApp(const MyApp());

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

enum UiPhase {
  scanning, // 카메라 움직여 평면 스캔
  planeFound, // 평면 감지됨
  chooseStart, // 시작점 탭 대기
  chooseEnd, // 도착점 탭 대기
  drawing, // 경로 생성 중
  done, // 경로 배치 완료
  trackingLost, // 추적 불안정
  error, // 예외
}

class _ArCoreExampleState extends State<ArCoreExample> {
  ArCoreController? arCoreController;

  UiPhase _phase = UiPhase.scanning;
  vector.Vector3? _startPos;
  final List<String> _routeNodeNames = [];

  @override
  void dispose() {
    arCoreController?.dispose();
    super.dispose();
  }

  void _setPhase(UiPhase p, {String? toast}) {
    setState(() => _phase = p);
    if (toast != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(toast)));
    }
  }

  void _onArCoreViewCreated(ArCoreController controller) {
    arCoreController = controller;

    // 평면 감지 이벤트 (지원되는 버전 기준)
    try {
      arCoreController!.onPlaneDetected = (ArCorePlane plane) {
        if (_phase == UiPhase.scanning) {
          _setPhase(UiPhase.planeFound, toast: '평면 감지됨 ✓  이제 시작점을 탭하세요');
          // 바로 시작점 안내
          _setPhase(UiPhase.chooseStart);
        }
      };
    } catch (_) {
      // 콜백 미지원 버전이면 무시
    }

    // 평면 탭 이벤트
    arCoreController!.onPlaneTap = (hits) async {
      if (arCoreController == null) return;

      // 히트가 없으면 스캔 유도
      if (hits.isEmpty) {
        _setPhase(UiPhase.scanning, toast: '평면 인식이 약해요. 밝은 곳에서 바닥을 더 스캔해 주세요.');
        return;
      }

      final hit = hits.first;
      final pos = hit.pose.translation;

      // 시작점 선택
      if (_startPos == null) {
        _startPos = pos;
        await _addMarkerSphere(
          _startPos!,
          color: Colors.green,
          name: 'start_marker',
        );
        _setPhase(UiPhase.chooseEnd, toast: '시작점 설정! 이제 도착점을 탭하세요.');
        return;
      }

      // 도착점 선택 → 경로 그리기
      _setPhase(UiPhase.drawing);
      final endPos = pos;
      await _clearRoute();
      await _placeRouteDots(_startPos!, endPos); // 빨간 점들
      _startPos = null;
      _setPhase(UiPhase.done, toast: '경로 표시 완료! (다시 두 번 탭하면 갱신)');
    };
  }

  // 경로를 0.5m 간격 빨간 점으로 표시
  Future<void> _placeRouteDots(vector.Vector3 from, vector.Vector3 to) async {
    try {
      final startY = from.y;
      final a = vector.Vector3(from.x, startY, from.z);
      final b = vector.Vector3(to.x, startY, to.z);

      final dir = b - a;
      final len = dir.length;
      if (len < 0.05) return;

      const step = 0.5; // 0.5m
      final count = (len / step).floor();
      final unit = dir / len;
      final lift = vector.Vector3(0, 0.01, 0); // 1cm 띄우기 (Z-fighting 방지)

      for (int i = 1; i <= count; i++) {
        final pos = a + unit * (step * i) + lift;
        final name = 'route_dot_$i';
        await _addDot(pos, name: name);
        _routeNodeNames.add(name);
      }
    } catch (e) {
      _setPhase(UiPhase.error, toast: '경로 표시 중 오류: $e');
    }
  }

  // 빨간 점
  Future<void> _addDot(vector.Vector3 position, {required String name}) async {
    final material = ArCoreMaterial(color: Colors.red, metallic: 0.6);
    final sphere = ArCoreSphere(materials: [material], radius: 0.06);
    final node = ArCoreNode(name: name, shape: sphere, position: position);
    await arCoreController!.addArCoreNodeWithAnchor(node);
  }

  // 시작점 마커(초록)
  Future<void> _addMarkerSphere(
    vector.Vector3 position, {
    required Color color,
    required String name,
  }) async {
    final material = ArCoreMaterial(color: color);
    final sphere = ArCoreSphere(materials: [material], radius: 0.07);
    final node = ArCoreNode(name: name, shape: sphere, position: position);
    await arCoreController!.addArCoreNodeWithAnchor(node);
  }

  // 경로/마커 지우기
  Future<void> _clearRoute() async {
    for (final name in _routeNodeNames) {
      try {
        await arCoreController!.removeNode(nodeName: name);
      } catch (_) {}
    }
    _routeNodeNames.clear();
    try {
      await arCoreController!.removeNode(nodeName: 'start_marker');
    } catch (_) {}
  }

  // 상단 상태 배너 메시지
  String get _statusText {
    switch (_phase) {
      case UiPhase.scanning:
        return '카메라를 천천히 움직여 평면을 스캔하세요';
      case UiPhase.planeFound:
        return '평면 감지됨 ✓';
      case UiPhase.chooseStart:
        return '시작점을 탭하세요';
      case UiPhase.chooseEnd:
        return '도착점을 탭하세요';
      case UiPhase.drawing:
        return '경로 표시 중...';
      case UiPhase.done:
        return '경로가 표시되었습니다 (다시 두 번 탭하면 갱신)';
      case UiPhase.trackingLost:
        return '트래킹이 불안정합니다. 카메라를 천천히 움직여주세요';
      case UiPhase.error:
        return '오류가 발생했습니다. 로그를 확인하세요';
    }
  }

  IconData get _statusIcon {
    switch (_phase) {
      case UiPhase.scanning:
        return Icons.camera_outlined;
      case UiPhase.planeFound:
        return Icons.check_circle_outline;
      case UiPhase.chooseStart:
        return Icons.my_location_outlined;
      case UiPhase.chooseEnd:
        return Icons.flag_outlined;
      case UiPhase.drawing:
        return Icons.timeline;
      case UiPhase.done:
        return Icons.route;
      case UiPhase.trackingLost:
        return Icons.warning_amber_outlined;
      case UiPhase.error:
        return Icons.error_outline;
    }
  }

  Color get _statusColor {
    switch (_phase) {
      case UiPhase.scanning:
        return Colors.blueGrey.shade700;
      case UiPhase.planeFound:
        return Colors.teal.shade700;
      case UiPhase.chooseStart:
        return Colors.indigo.shade700;
      case UiPhase.chooseEnd:
        return Colors.deepPurple.shade700;
      case UiPhase.drawing:
        return Colors.orange.shade800;
      case UiPhase.done:
        return Colors.green.shade700;
      case UiPhase.trackingLost:
        return Colors.red.shade700;
      case UiPhase.error:
        return Colors.red.shade900;
    }
  }

  Future<void> _resetAll() async {
    await _clearRoute();
    _startPos = null;
    _setPhase(UiPhase.scanning, toast: '초기화 완료. 평면을 다시 스캔하세요.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ARCore Evac Route")),
      body: Stack(
        children: [
          ArCoreView(
            onArCoreViewCreated: _onArCoreViewCreated,
            enableTapRecognizer: true,
          ),

          // 상단 상태 배너
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(blurRadius: 8, color: Colors.black26),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        _statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // 리셋 버튼
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _resetAll,
        icon: const Icon(Icons.refresh),
        label: const Text('리셋'),
      ),
    );
  }
}
