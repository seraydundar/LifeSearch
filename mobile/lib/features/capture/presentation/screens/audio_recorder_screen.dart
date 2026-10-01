import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Pops with the recorded clip's local file path, or `null` if cancelled.
class AudioRecorderScreen extends StatefulWidget {
  const AudioRecorderScreen({super.key});

  @override
  State<AudioRecorderScreen> createState() => _AudioRecorderScreenState();
}

class _AudioRecorderScreenState extends State<AudioRecorderScreen> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _error;
  String? _recordedPath;

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Mikrofon izni verilmedi. Ayarlardan izin ver.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        _isRecording = true;
        _elapsed = Duration.zero;
        _error = null;
      });
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _elapsed += const Duration(seconds: 1)),
      );
    } catch (_) {
      setState(() => _error = 'Kayıt başlatılamadı. Tekrar dene.');
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _recordedPath = path;
    });
  }

  void _finish() => Navigator.of(context).pop(_recordedPath);

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final hasRecording = _recordedPath != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Record Audio')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
              ],
              Text(_format(_elapsed), style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _isRecording ? _stop : (hasRecording ? null : _start),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              if (hasRecording)
                FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.check),
                  label: const Text('Kaydet'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
