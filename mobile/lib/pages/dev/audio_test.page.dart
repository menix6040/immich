import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:immich_mobile/presentation/widgets/memory/memory_music_tracks.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioTestPage extends StatefulWidget {
  const AudioTestPage({super.key});

  @override
  State<AudioTestPage> createState() => _AudioTestPageState();
}

class _AudioTestPageState extends State<AudioTestPage> {
  late final AudioPlayer _player;
  String _currentTrack = memoryMusicTracks.first;
  String? _lastError;
  final Map<String, String> _assetCache = {};

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playTrackFromFile(String track) async {
    setState(() {
      _currentTrack = track;
      _lastError = null;
    });
    try {
      final cachedPath = await _cacheAssetToFile(track);
      await _player.setAudioSource(AudioSource.file(cachedPath));
      await _player.play();
    } catch (e) {
      setState(() {
        _lastError = e.toString();
      });
    }
  }

  Future<void> _stop() async {
    await _player.stop();
  }

  Future<String> _cacheAssetToFile(String assetPath) async {
    final cached = _assetCache[assetPath];
    if (cached != null && await File(cached).exists()) {
      return cached;
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'memory_audio_test', p.basename(assetPath)));
    await file.parent.create(recursive: true);

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await file.writeAsBytes(bytes, flush: true);

    _assetCache[assetPath] = file.path;
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final state = snapshot.data;
                final processing = state?.processingState.toString() ?? 'unknown';
                final playing = state?.playing == true;
                return Row(
                  children: [
                    Expanded(child: Text('Track: $_currentTrack')),
                    Text(playing ? 'playing' : 'stopped'),
                    const SizedBox(width: 12),
                    Text(processing),
                  ],
                );
              },
            ),
          ),
          if (_lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_lastError!, style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () => _playTrackFromFile(_currentTrack),
                  child: const Text('Play'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _stop,
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: memoryMusicTracks.length,
              itemBuilder: (context, index) {
                final track = memoryMusicTracks[index];
                return ListTile(
                  title: Text(track),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => _playTrackFromFile(track),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
