import 'package:e_ambulance/models/traffic_light_status.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> snapshot() => {
  'v': 2,
  'intersection': 'khulna_royal_mor',
  'lights': {'north': 'red', 'east': 'green', 'south': 'red', 'west': 'red'},
  'mode': 'manual',
  'phase': 'green',
  'target': 'east',
  'uptime': 42,
  'auth': true,
  'seq': 17,
  'ack': 'request-1',
  'error': '',
};

void main() {
  test('decodes complete v2 telemetry and command correlation', () {
    final status = TrafficLightStatus.fromJson(snapshot());
    expect(status.supportsFourWay, isTrue);
    expect(status.lights.keys, kTrafficDirections);
    expect(status.lightFor('east'), 'green');
    expect(status.lightFor('south'), 'red');
    expect(status.intersectionId, 'khulna_royal_mor');
    expect(status.ackId, 'request-1');
    expect(status.errorCode, isNull);
    expect(status.authOk, isTrue);
    expect(() => status.lights['north'] = 'green', throwsUnsupportedError);
  });

  test(
    'legacy single-lamp status never fabricates four red lights or auth',
    () {
      final status = TrafficLightStatus.fromJson({
        'light': 'red',
        'mode': 'manual',
      });
      expect(status.supportsFourWay, isFalse);
      expect(status.authOk, isFalse);
      expect(
        kTrafficDirections.every((dir) => status.lightFor(dir) == 'unknown'),
        isTrue,
      );
    },
  );

  test('conflicting non-red lamps are incompatible', () {
    for (final color in ['green', 'yellow']) {
      final data = snapshot();
      (data['lights'] as Map)['north'] = color;
      expect(TrafficLightStatus.fromJson(data).supportsFourWay, isFalse);
    }
  });

  test('phase must agree with reported lamps', () {
    for (final phase in ['all_red', 'yellow', 'invalid']) {
      expect(
        TrafficLightStatus.fromJson({...snapshot(), 'phase': phase})
            .supportsFourWay,
        isFalse,
      );
    }
    final data = snapshot();
    (data['lights'] as Map)['east'] = 'yellow';
    data['phase'] = 'yellow';
    data['target'] = '';
    expect(TrafficLightStatus.fromJson(data).supportsFourWay, isTrue);
    (data['lights'] as Map)['east'] = 'red';
    data['phase'] = 'all_red';
    expect(TrafficLightStatus.fromJson(data).supportsFourWay, isTrue);
  });

  test('missing lamp is unknown, not an assumed physical red', () {
    final data = snapshot();
    (data['lights'] as Map).remove('north');
    final status = TrafficLightStatus.fromJson(data);
    expect(status.lightFor('north'), 'unknown');
    expect(status.supportsFourWay, isFalse);
  });

  test(
    'incomplete or wrongly typed v2 envelopes cannot acknowledge commands',
    () {
      for (final field in [
        'lights',
        'intersection',
        'mode',
        'phase',
        'target',
        'uptime',
        'auth',
        'seq',
        'ack',
        'error',
      ]) {
        final data = snapshot()..remove(field);
        expect(
          () => TrafficLightStatus.fromJson(data),
          throwsFormatException,
          reason: field,
        );
      }
      for (final data in [
        {...snapshot(), 'seq': 2.2},
        {...snapshot(), 'error': false},
        {...snapshot(), 'auth': 'true'},
      ]) {
        expect(() => TrafficLightStatus.fromJson(data), throwsFormatException);
      }
      expect(
        TrafficLightStatus.fromJson({...snapshot(), 'v': 2.5}).supportsFourWay,
        isFalse,
      );
    },
  );

  test('acknowledgement errors and empty IDs are preserved honestly', () {
    final status = TrafficLightStatus.fromJson({
      ...snapshot(),
      'error': 'busy',
      'ack': '',
    });
    expect(status.errorCode, 'busy');
    expect(status.ackId, isNull);
  });

  test('uint32 sequence boundaries and unknown directions are validated', () {
    expect(
      TrafficLightStatus.fromJson({...snapshot(), 'seq': 0xffffffff})
          .supportsFourWay,
      isTrue,
    );
    expect(
      TrafficLightStatus.fromJson({...snapshot(), 'seq': -1}).supportsFourWay,
      isFalse,
    );
    expect(
      TrafficLightStatus.fromJson({...snapshot(), 'seq': 0x100000000})
          .supportsFourWay,
      isFalse,
    );
    expect(
      TrafficLightStatus.fromJson({...snapshot(), 'target': 'all'})
          .supportsFourWay,
      isFalse,
    );
  });

  test(
    'directional commands are explicit; ambiguous legacy/all-green rejected',
    () {
      for (final dir in kTrafficDirections) {
        for (final light in ['red', 'yellow', 'green']) {
          expect(TrafficLightCommand.set(dir, light), {
            'cmd': 'SET',
            'direction': dir,
            'light': light,
          });
        }
      }
      for (final dir in ['', 'all', 'NORTH']) {
        expect(
          () => TrafficLightCommand.set(dir, 'green'),
          throwsArgumentError,
        );
      }
      expect(
        () => TrafficLightCommand.set('north', 'blue'),
        throwsArgumentError,
      );
    },
  );

  test('auto timing matches firmware limits without silent clamping', () {
    expect(
      TrafficLightCommand.automatic(greenSec: 5, yellowSec: 3, allRedSec: 2),
      {'cmd': 'AUTO', 'green_sec': 5, 'yellow_sec': 3, 'all_red_sec': 2},
    );
    expect(
      TrafficLightCommand.automatic(
        greenSec: 300,
        yellowSec: 60,
        allRedSec: 60,
      )['all_red_sec'],
      60,
    );
    for (final values in [
      [4, 3, 2],
      [301, 3, 2],
      [5, 2, 2],
      [5, 61, 2],
      [5, 3, 1],
      [5, 3, 61],
    ]) {
      expect(
        () => TrafficLightCommand.automatic(
          greenSec: values[0],
          yellowSec: values[1],
          allRedSec: values[2],
        ),
        throwsArgumentError,
      );
    }
  });
}
