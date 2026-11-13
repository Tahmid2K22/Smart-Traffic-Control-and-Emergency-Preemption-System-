const kTrafficDirections = ['north', 'east', 'south', 'west'];

class TrafficLightStatus {
  const TrafficLightStatus({
    required this.version,
    required this.intersectionId,
    required this.lights,
    required this.mode,
    required this.phase,
    required this.uptime,
    required this.authOk,
    required this.sequence,
    this.targetDirection,
    this.ackId,
    this.errorCode,
  });

  final int version;
  final String intersectionId;
  final Map<String, String> lights;
  final String mode;
  final String phase;
  final String? targetDirection;
  final int uptime;
  final bool authOk;
  final int sequence;
  final String? ackId;
  final String? errorCode;

  String lightFor(String direction) => lights[direction] ?? 'unknown';

  bool get supportsFourWay =>
      version == 2 &&
      intersectionId.isNotEmpty &&
      uptime >= 0 &&
      sequence >= 0 &&
      sequence <= 0xffffffff &&
      const ['manual', 'auto'].contains(mode) &&
      const ['green', 'yellow', 'all_red'].contains(phase) &&
      kTrafficDirections.every(
        (direction) =>
            const ['red', 'yellow', 'green'].contains(lights[direction]),
      ) &&
      _phaseMatchesLights &&
      (targetDirection == null || kTrafficDirections.contains(targetDirection));

  bool get _phaseMatchesLights {
    final green = lights.values.where((color) => color == 'green').length;
    final yellow = lights.values.where((color) => color == 'yellow').length;
    return switch (phase) {
      'green' => green == 1 && yellow == 0,
      'yellow' => green == 0 && yellow == 1,
      'all_red' => green == 0 && yellow == 0,
      _ => false,
    };
  }

  factory TrafficLightStatus.fromJson(Map<String, dynamic> data) {
    if (data['v'] is int &&
        data['v'] == 2 &&
        (data['intersection'] is! String ||
            data['lights'] is! Map ||
            data['mode'] is! String ||
            data['phase'] is! String ||
            data['target'] is! String ||
            data['uptime'] is! int ||
            data['seq'] is! int ||
            data['auth'] is! bool ||
            data['ack'] is! String ||
            data['error'] is! String)) {
      throw const FormatException(
        'Incomplete or malformed four-way telemetry.',
      );
    }
    String? optional(dynamic value) =>
        value is String && value.isNotEmpty ? value : null;
    final rawLights = data['lights'];
    return TrafficLightStatus(
      version: data['v'] is int ? data['v'] as int : 1,
      intersectionId: data['intersection'] as String? ?? '',
      lights: Map.unmodifiable({
        for (final direction in kTrafficDirections)
          direction: rawLights is Map && rawLights[direction] is String
              ? rawLights[direction] as String
              : 'unknown',
      }),
      mode: data['mode'] as String? ?? 'unknown',
      phase: data['phase'] as String? ?? 'unknown',
      targetDirection: optional(data['target']),
      uptime: (data['uptime'] as num?)?.toInt() ?? 0,
      authOk: data['auth'] == true,
      sequence: (data['seq'] as num?)?.toInt() ?? 0,
      ackId: optional(data['ack']),
      errorCode: optional(data['error']),
    );
  }
}

/// Shared validation prevents ambiguous legacy commands and out-of-range timers.
class TrafficLightCommand {
  static Map<String, dynamic> set(String direction, String light) {
    if (!kTrafficDirections.contains(direction) ||
        !const ['red', 'yellow', 'green'].contains(light)) {
      throw ArgumentError('Select a valid direction and signal color.');
    }
    return {'cmd': 'SET', 'direction': direction, 'light': light};
  }

  static Map<String, dynamic> automatic({
    required int greenSec,
    required int yellowSec,
    required int allRedSec,
  }) {
    if (greenSec < 5 ||
        greenSec > 300 ||
        yellowSec < 3 ||
        yellowSec > 60 ||
        allRedSec < 2 ||
        allRedSec > 60) {
      throw ArgumentError(
        'Green must be 5–300 s, yellow 3–60 s, and all-red 2–60 s.',
      );
    }
    return {
      'cmd': 'AUTO',
      'green_sec': greenSec,
      'yellow_sec': yellowSec,
      'all_red_sec': allRedSec,
    };
  }
}
