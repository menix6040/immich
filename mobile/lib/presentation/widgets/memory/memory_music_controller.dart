import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:immich_mobile/presentation/widgets/memory/memory_music_tracks.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MemoryMusicController {
  MemoryMusicController({double volume = 0.35, bool enabled = true})
    : _volume = volume,
      _enabled = enabled;

  double _volume;
  bool _enabled;
  final AudioPlayer _player = AudioPlayer();
  final Duration _fadeInDuration = const Duration(milliseconds: 800);
  final Duration _fadeOutDuration = const Duration(milliseconds: 600);
  final int _fadeSteps = 12;
  final Map<String, String> _assetCache = {};
  bool _isPrecacheStarted = false;

  String? _currentKey;
  String? _pendingKey;
  bool _isSwitching = false;
  bool _isDisposed = false;
  final Map<String, String> _trackByKey = {};
  final Random _random = Random();
  late final List<String> _shuffledTracks = List<String>.from(memoryMusicTracks)..shuffle(_random);
  int _nextTrackIndex = 0;

  Future<void> changeMemory(String key) async {
    if (_isDisposed || !_enabled) {
      return;
    }

    if (_currentKey == null) {
      if (await _startForKey(key)) {
        _currentKey = key;
      }
      return;
    }

    if (key == _currentKey) {
      return;
    }

    if (_isSwitching) {
      _pendingKey = key;
      return;
    }

    _isSwitching = true;
    try {
      await _switchToKey(key);
    } finally {
      _isSwitching = false;
    }

    final pending = _pendingKey;
    _pendingKey = null;
    if (pending != null && pending != _currentKey) {
      await changeMemory(pending);
    }
  }

  Future<void> shutdown() async {
    if (_isDisposed) {
      return;
    }

    await _fadeTo(0.0, duration: _fadeOutDuration);
    await _player.stop();
    await _player.dispose();
    _isDisposed = true;
  }

  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }
    await _fadeTo(0.0, duration: _fadeOutDuration);
    await _player.stop();
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) {
      await stop();
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (!_isDisposed) {
      await _player.setVolume(_volume);
    }
  }

  Future<void> _switchToKey(String key) async {
    await _fadeTo(0.0, duration: _fadeOutDuration);
    await _player.stop();
    if (await _startForKey(key)) {
      _currentKey = key;
    } else {
      _currentKey = null;
    }
  }

  Future<bool> _startForKey(String key) async {
    final tried = <String>{};
    while (tried.length < memoryMusicTracks.length) {
      final track = _trackForKey(key, exclude: tried);
      tried.add(track);
      try {
        final cachedPath = await _cacheAssetToFile(track);
        await _player.setAudioSource(AudioSource.file(cachedPath));
        await _player.setLoopMode(LoopMode.one);
        await _player.setVolume(0.0);
        await _player.play();
        await _fadeTo(_volume, duration: _fadeInDuration);
        return true;
      } catch (e) {
        _trackByKey.remove(key);
      }
    }
    return false;
  }

  Future<void> _fadeTo(double target, {required Duration duration}) async {
    if (_isDisposed) {
      return;
    }

    final start = _player.volume;
    final step = (target - start) / _fadeSteps;
    final delay = Duration(microseconds: duration.inMicroseconds ~/ _fadeSteps);

    for (int i = 1; i <= _fadeSteps; i++) {
      if (_isDisposed) {
        return;
      }
      final next = (start + (step * i)).clamp(0.0, 1.0);
      await _player.setVolume(next);
      if (i < _fadeSteps) {
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<String> _cacheAssetToFile(String assetPath) async {
    final cached = _assetCache[assetPath];
    if (cached != null && await File(cached).exists()) {
      return cached;
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'memory_audio', p.basename(assetPath)));
    await file.parent.create(recursive: true);

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await file.writeAsBytes(bytes, flush: true);

    _assetCache[assetPath] = file.path;
    return file.path;
  }

  Future<void> precacheAll() async {
    if (_isDisposed || _isPrecacheStarted) {
      return;
    }
    _isPrecacheStarted = true;
    for (final track in memoryMusicTracks) {
      if (_isDisposed) {
        return;
      }
      await _cacheAssetToFile(track);
    }
  }

  String _trackForKey(String key, {Set<String>? exclude}) {
    final existing = _trackByKey[key];
    if (existing != null && (exclude == null || !exclude.contains(existing))) {
      return existing;
    }

    final available = exclude == null ? _shuffledTracks : _shuffledTracks.where((t) => !exclude.contains(t)).toList();
    final track = available[_nextTrackIndex % available.length];
    _nextTrackIndex = (_nextTrackIndex + 1) % _shuffledTracks.length;
    _trackByKey[key] = track;
    return track;
  }
}
