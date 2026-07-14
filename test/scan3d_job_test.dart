import 'package:dating_app/data/models/scan3d_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Scan3dStatus.fromWire', () {
    test('parses known statuses', () {
      expect(Scan3dStatus.fromWire('created'), Scan3dStatus.created);
      expect(Scan3dStatus.fromWire('uploading'), Scan3dStatus.uploading);
      expect(Scan3dStatus.fromWire('processing'), Scan3dStatus.processing);
      expect(Scan3dStatus.fromWire('ready'), Scan3dStatus.ready);
      expect(Scan3dStatus.fromWire('failed'), Scan3dStatus.failed);
    });

    test('is case- and whitespace-insensitive', () {
      expect(Scan3dStatus.fromWire('  READY  '), Scan3dStatus.ready);
      expect(Scan3dStatus.fromWire('Failed'), Scan3dStatus.failed);
    });

    test('maps synonyms to canonical statuses', () {
      expect(Scan3dStatus.fromWire('queued'), Scan3dStatus.created);
      expect(Scan3dStatus.fromWire('running'), Scan3dStatus.processing);
      expect(Scan3dStatus.fromWire('completed'), Scan3dStatus.ready);
      expect(Scan3dStatus.fromWire('error'), Scan3dStatus.failed);
    });

    test('unknown / null status falls back to processing (safe default)', () {
      expect(Scan3dStatus.fromWire('teleporting'), Scan3dStatus.processing);
      expect(Scan3dStatus.fromWire(''), Scan3dStatus.processing);
      expect(Scan3dStatus.fromWire(null), Scan3dStatus.processing);
    });

    test('wire round-trips for every status', () {
      for (final s in Scan3dStatus.values) {
        expect(Scan3dStatus.fromWire(s.wire), s);
      }
    });
  });

  group('Scan3dJob JSON round-trip', () {
    test('ready job with both assets round-trips', () {
      const job = Scan3dJob(
        jobId: 'job-123',
        status: Scan3dStatus.ready,
        meshGlbUrl: 'https://cdn.example.com/a.glb',
        splatUrl: 'https://cdn.example.com/a.ply',
      );

      final restored = Scan3dJob.fromJson(job.toJson());

      expect(restored.jobId, 'job-123');
      expect(restored.status, Scan3dStatus.ready);
      expect(restored.meshGlbUrl, 'https://cdn.example.com/a.glb');
      expect(restored.splatUrl, 'https://cdn.example.com/a.ply');
      expect(restored.error, isNull);
      expect(restored.isReady, isTrue);
      expect(restored.hasAssets, isTrue);
    });

    test('failed job round-trips with error and no assets', () {
      const job = Scan3dJob(
        jobId: 'job-9',
        status: Scan3dStatus.failed,
        error: 'bad capture',
      );

      final restored = Scan3dJob.fromJson(job.toJson());

      expect(restored.status, Scan3dStatus.failed);
      expect(restored.error, 'bad capture');
      expect(restored.meshGlbUrl, isNull);
      expect(restored.splatUrl, isNull);
      expect(restored.isFailed, isTrue);
      expect(restored.isTerminal, isTrue);
      expect(restored.hasAssets, isFalse);
    });

    test('toJson omits null optional fields', () {
      const job = Scan3dJob(jobId: 'j', status: Scan3dStatus.processing);
      final map = job.toJson();
      expect(map.containsKey('meshGlbUrl'), isFalse);
      expect(map.containsKey('splatUrl'), isFalse);
      expect(map.containsKey('error'), isFalse);
      expect(map['status'], 'processing');
    });
  });

  group('Scan3dJob.fromJson tolerance', () {
    test('reads a backend GET /scan3d/{jobId} ready payload', () {
      final job = Scan3dJob.fromJson({
        'jobId': 'job-abc',
        'status': 'ready',
        'meshGlbUrl': 'https://x/m.glb',
        'splatUrl': 'https://x/s.ply',
      });
      expect(job.jobId, 'job-abc');
      expect(job.isReady, isTrue);
      expect(job.meshGlbUrl, 'https://x/m.glb');
      expect(job.splatUrl, 'https://x/s.ply');
    });

    test('unwraps a payload nested under "data"', () {
      final job = Scan3dJob.fromJson({
        'data': {
          'jobId': 'nested-1',
          'status': 'processing',
        },
      });
      expect(job.jobId, 'nested-1');
      expect(job.status, Scan3dStatus.processing);
    });

    test('accepts snake_case asset keys and "id" alias', () {
      final job = Scan3dJob.fromJson({
        'id': 'snake-1',
        'status': 'ready',
        'mesh_glb_url': 'https://x/m.glb',
        'splat_url': 'https://x/s.ply',
      });
      expect(job.jobId, 'snake-1');
      expect(job.meshGlbUrl, 'https://x/m.glb');
      expect(job.splatUrl, 'https://x/s.ply');
    });

    test('unknown status string yields processing, not a crash', () {
      final job = Scan3dJob.fromJson({'jobId': 'j', 'status': 'wat'});
      expect(job.status, Scan3dStatus.processing);
    });

    test('empty / blank asset strings become null', () {
      final job = Scan3dJob.fromJson({
        'jobId': 'j',
        'status': 'ready',
        'meshGlbUrl': '',
        'splatUrl': '   ',
      });
      expect(job.meshGlbUrl, isNull);
      expect(job.splatUrl, isNull);
      expect(job.hasAssets, isFalse);
    });

    test('copyWith preserves other fields', () {
      const job = Scan3dJob(jobId: 'j', status: Scan3dStatus.processing);
      final updated = job.copyWith(jobId: 'j2');
      expect(updated.jobId, 'j2');
      expect(updated.status, Scan3dStatus.processing);
    });

    test('a poll-timeout job is NOT terminal/failed — record must be kept', () {
      // Invariant _CloudReconstructScreen relies on: a client poll timeout is
      // 'processing' + timedOut, so it is neither terminal nor failed and the
      // PendingScanStore record survives for the background finalizer. If someone
      // makes the timeout status 'failed' again, isTerminal flips and the billed
      // reconstruction gets orphaned — this catches that regression.
      const t = Scan3dJob(
          jobId: 'j', status: Scan3dStatus.processing, timedOut: true);
      expect(t.timedOut, isTrue);
      expect(t.isTerminal, isFalse);
      expect(t.isFailed, isFalse);
      expect(t.copyWith(jobId: 'j2').timedOut, isTrue); // survives copyWith
    });
  });
}
