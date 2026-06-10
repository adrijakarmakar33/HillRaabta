import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  final List<PlatformFile> _tracks = [];
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickMusic() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
      );
      if (result == null || result.files.isEmpty) return;

      final files = result.files.where((f) => f.path != null).toList();
      if (files.isEmpty) return;

      final sources = files
          .map((f) => AudioSource.uri(Uri.file(f.path!)))
          .toList(growable: false);

      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: 0,
      );

      setState(() {
        _tracks
          ..clear()
          ..addAll(files);
      });
      await _player.play();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D9E75),
        title: const Text(
          'Offline Music',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _pickMusic,
                icon: const Icon(Icons.library_music),
                label: Text(_loading ? 'Loading...' : 'Pick songs from phone'),
              ),
            ),
          ),
          _PlayerControls(player: _player),
          const Divider(height: 1),
          Expanded(
            child: _tracks.isEmpty
                ? const Center(
                    child: Text(
                      'No songs loaded yet.\nPick songs to play offline.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : StreamBuilder<int?>(
                    stream: _player.currentIndexStream,
                    builder: (context, snapshot) {
                      final currentIndex = snapshot.data ?? -1;
                      return ListView.builder(
                        itemCount: _tracks.length,
                        itemBuilder: (context, i) {
                          final file = _tracks[i];
                          final active = i == currentIndex;
                          return ListTile(
                            leading: Icon(
                              active ? Icons.equalizer : Icons.music_note,
                              color: active ? const Color(0xFF1D9E75) : null,
                            ),
                            title: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: file.path == null
                                ? null
                                : Text(
                                    File(file.path!).parent.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => _playTrack(i),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final AudioPlayer player;

  const _PlayerControls({required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, posSnap) {
              final position = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: player.durationStream,
                builder: (context, durSnap) {
                  final duration = durSnap.data ?? const Duration(seconds: 1);
                  final maxMillis = duration.inMilliseconds <= 0
                      ? 1
                      : duration.inMilliseconds;
                  final value =
                      position.inMilliseconds.clamp(0, maxMillis).toDouble();
                  return Column(
                    children: [
                      Slider(
                        value: value,
                        max: maxMillis.toDouble(),
                        onChanged: (v) =>
                            player.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(position)),
                          Text(_fmt(duration)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: player.hasPrevious ? player.seekToPrevious : null,
                icon: const Icon(Icons.skip_previous),
              ),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  final processing = state?.processingState;
                  final playing = state?.playing ?? false;

                  if (processing == ProcessingState.loading ||
                      processing == ProcessingState.buffering) {
                    return const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  return IconButton(
                    onPressed: playing ? player.pause : player.play,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    iconSize: 36,
                  );
                },
              ),
              IconButton(
                onPressed: player.hasNext ? player.seekToNext : null,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '${hh.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
  }
}
