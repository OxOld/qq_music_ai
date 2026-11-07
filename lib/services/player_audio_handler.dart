import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'player_service.dart';

/// audio_service 桥接：把 PlayerService 的状态提交给系统媒体通知/锁屏。
///
/// 通知动作固定为 [上一首, 播放/暂停, 下一首]（无停止方块），
/// 小图标使用 ic_notification（白色音符）。
class PlayerAudioHandler extends BaseAudioHandler with SeekHandler {
  final PlayerService _service;
  Timer? _positionTimer;
  Duration _position = Duration.zero;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _changeSub;

  PlayerAudioHandler(this._service) {
    _stateSub = _service.stateStream.listen((_) => _broadcast());
    _posSub = _service.positionStream.listen((p) {
      _position = p;
      _broadcast();
    });
    _changeSub = _service.changeStream.listen((_) {
      _broadcastMediaItem();
      _broadcast();
    });
    _broadcastMediaItem();
    _broadcast();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_service.playing) _broadcast();
    });
  }

  void _broadcastMediaItem() {
    mediaItem.add(MediaItem(
      id: 'qq_music_${_service.index}_${_service.queueLength}',
      title: _service.currentTitle ?? '未在播放',
      artist: 'QQ 音乐',
      artUri: (_service.currentCover != null &&
              _service.currentCover!.isNotEmpty)
          ? Uri.tryParse(_service.currentCover!)
          : null,
    ));
  }

  void _broadcast() {
    final controls = <MediaControl>[
      if (_service.hasQueue) ...[
        MediaControl.skipToPrevious,
        _service.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
    ];
    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      processingState: _service.hasQueue
          ? AudioProcessingState.ready
          : AudioProcessingState.idle,
      playing: _service.playing,
      updatePosition: _position,
    ));
  }

  @override
  Future<void> play() => _service.resume();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> skipToNext() => _service.next();

  @override
  Future<void> skipToPrevious() => _service.previous();

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> stop() async {
    await _service.pause();
    await super.stop();
  }

  Future<void> dispose() async {
    _positionTimer?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _changeSub?.cancel();
  }
}
