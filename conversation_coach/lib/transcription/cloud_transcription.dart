import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'transcription_engine.dart';

/// Cloud transcription adapter (Tech Spec §6.2) — a managed ASR with
/// diarization, multilingual coverage and code-switching. Audio leaves the
/// device only on explicit opt-in (Tech Spec §8 — data minimisation).
///
/// This adapter targets an OpenAI-style multipart `/audio/transcriptions`
/// endpoint, which most managed ASR providers expose. The endpoint and key are
/// supplied by the user's provider configuration; the key is read from the
/// keystore at call time and never persisted here.
///
/// Whisper rejects uploads over 25 MB, and our recordings are uncompressed WAV
/// (~5 MB/min mono, ~11 MB/min stereo) — so a long meeting must be split into
/// frame-aligned chunks, each transcribed separately and stitched back together
/// with offset timestamps. Chunks are read straight off disk so we never hold
/// the whole (potentially hundreds-of-MB) recording in memory.
class CloudTranscriptionEngine implements TranscriptionEngine {
  final String endpointUrl;
  final String? apiKey;
  final String model;
  final http.Client _http;

  /// Stay comfortably under Whisper's 25 MB request limit (the multipart
  /// envelope and WAV header add a little overhead on top of the audio).
  static const int _maxChunkBytes = 20 * 1024 * 1024;

  CloudTranscriptionEngine({
    required this.endpointUrl,
    required this.apiKey,
    this.model = 'whisper-1',
    http.Client? client,
  }) : _http = client ?? http.Client();

  @override
  String get id => 'cloud-asr';

  @override
  String get displayName => 'Cloud transcription (higher accuracy)';

  @override
  bool get sendsAudioToCloud => true;

  @override
  Future<TranscriptionResult> transcribe({
    required String audioPath,
    required List<String> languages,
    int channels = 1,
  }) async {
    final file = File(audioPath);
    final totalLen = await file.length();

    // Small enough for a single request, or not a WAV we can split — send as-is.
    if (totalLen <= _maxChunkBytes) {
      final part = await http.MultipartFile.fromPath('file', audioPath);
      return _send(part, languages);
    }

    final raf = await file.open();
    try {
      // Read enough of the head to clear any LIST/INFO chunks before `data`.
      final probe = await _readAt(raf, 0, min(65536, totalLen));
      final wav = _parseWavHeader(probe, totalLen);
      if (wav == null) {
        // Unknown/compressed container we can't chunk safely — try as one shot.
        final part = await http.MultipartFile.fromPath('file', audioPath);
        return _send(part, languages);
      }

      final blockAlign = wav.channels * (wav.bitsPerSample ~/ 8);
      final byteRate = wav.sampleRate * blockAlign;
      // Largest whole number of frames that fits under the limit.
      final maxChunk = max(blockAlign, (_maxChunkBytes ~/ blockAlign) * blockAlign);

      final turns = <TranscriptTurn>[];
      String? language;
      var offset = 0;
      while (offset < wav.dataLength) {
        final len = min(maxChunk, wav.dataLength - offset);
        await raf.setPosition(wav.dataOffset + offset);
        final pcm = await raf.read(len);
        final wavBytes = _buildWav(pcm, wav);
        final startMs = (offset / byteRate * 1000).round();

        final part = http.MultipartFile.fromBytes('file', wavBytes,
            filename: 'chunk.wav');
        final result = await _send(part, languages);
        language ??= result.language;
        for (final t in result.turns) {
          turns.add(TranscriptTurn(
            startMs: t.startMs + startMs,
            endMs: t.endMs + startMs,
            speakerTag: t.speakerTag,
            text: t.text,
          ));
        }
        offset += len;
      }

      return TranscriptionResult(
        turns: turns,
        language: language ?? (languages.isEmpty ? 'en' : languages.first),
      );
    } finally {
      await raf.close();
    }
  }

  /// Posts one audio part to the ASR endpoint and parses the response.
  Future<TranscriptionResult> _send(
      http.MultipartFile part, List<String> languages) async {
    final uri = Uri.parse(
        '${endpointUrl.replaceAll(RegExp(r'/+$'), '')}/audio/transcriptions');
    final req = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json'
      ..fields['timestamp_granularities[]'] = 'segment';
    if (languages.isNotEmpty) req.fields['language'] = languages.first;
    if ((apiKey ?? '').isNotEmpty) {
      req.headers['authorization'] = 'Bearer $apiKey';
    }
    req.files.add(part);

    final streamed = await _http.send(req);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw HttpException(
          'Transcription failed (${resp.statusCode}): ${resp.body}');
    }

    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final segments = (j['segments'] as List?) ?? const [];
    final turns = <TranscriptTurn>[];
    for (final s in segments) {
      final m = s as Map<String, dynamic>;
      final text = (m['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      // Without true diarization Whisper attributes everything to one speaker;
      // hardware channel separation (F-TRA-03) refines this upstream.
      turns.add(TranscriptTurn(
        startMs: (((m['start'] as num?)?.toDouble() ?? 0) * 1000).round(),
        endMs: (((m['end'] as num?)?.toDouble() ?? 0) * 1000).round(),
        speakerTag: 'S1',
        text: text,
      ));
    }

    // Fallback: a provider that returns only a flat "text" field (no segment
    // timestamps) still yields one usable turn.
    if (turns.isEmpty) {
      final text = (j['text'] as String? ?? '').trim();
      if (text.isNotEmpty) {
        turns.add(TranscriptTurn(
            startMs: 0, endMs: 0, speakerTag: 'S1', text: text));
      }
    }

    return TranscriptionResult(
      turns: turns,
      language: (j['language'] as String?) ??
          (languages.isEmpty ? 'en' : languages.first),
    );
  }

  Future<Uint8List> _readAt(RandomAccessFile raf, int pos, int len) async {
    await raf.setPosition(pos);
    return raf.read(len);
  }

  /// Parses a canonical RIFF/WAVE header, returning the PCM format and the byte
  /// offset/length of the `data` chunk. Returns null if it isn't a PCM WAV.
  _WavInfo? _parseWavHeader(Uint8List b, int totalLen) {
    if (b.length < 12) return null;
    if (_tag(b, 0) != 'RIFF' || _tag(b, 8) != 'WAVE') return null;

    int channels = 0, sampleRate = 0, bits = 0;
    int dataOffset = -1, dataLength = 0;
    var pos = 12;
    while (pos + 8 <= b.length) {
      final id = _tag(b, pos);
      final size = _u32(b, pos + 4);
      final body = pos + 8;
      if (id == 'fmt ' && body + 16 <= b.length) {
        channels = _u16(b, body + 2);
        sampleRate = _u32(b, body + 4);
        bits = _u16(b, body + 14);
      } else if (id == 'data') {
        dataOffset = body;
        dataLength = size;
        break; // audio data follows; we have what we need
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }

    if (dataOffset < 0 || sampleRate == 0 || channels == 0 || bits == 0) {
      return null;
    }
    // Streaming writers sometimes leave an absent/oversized data length; clamp
    // to what's actually on disk.
    if (dataLength <= 0 || dataOffset + dataLength > totalLen) {
      dataLength = totalLen - dataOffset;
    }
    return _WavInfo(
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bits,
      dataOffset: dataOffset,
      dataLength: dataLength,
    );
  }

  /// Builds a standalone canonical 44-byte-header PCM WAV around [pcm].
  Uint8List _buildWav(Uint8List pcm, _WavInfo w) {
    final blockAlign = w.channels * (w.bitsPerSample ~/ 8);
    final byteRate = w.sampleRate * blockAlign;
    final dataLen = pcm.length;
    final b = BytesBuilder();
    void str(String s) => b.add(ascii.encode(s));
    void u32(int v) => b.add(_le32(v));
    void u16(int v) => b.add(_le16(v));
    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(w.channels);
    u32(w.sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(w.bitsPerSample);
    str('data');
    u32(dataLen);
    b.add(pcm);
    return b.toBytes();
  }

  String _tag(Uint8List b, int i) => String.fromCharCodes(b.sublist(i, i + 4));
  int _u16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
  int _u32(Uint8List b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
  List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
  List<int> _le32(int v) =>
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
}

class _WavInfo {
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;
  const _WavInfo({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });
}
