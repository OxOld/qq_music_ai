import 'dart:async';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放模式
enum PlayMode { listLoop, singleLoop, sequential, shuffle }

/// 播放器服务
///
/// - ConcatenatingAudioSource 队列播放：系统媒体通知栏带上一首/播放暂停/下一首
///   （后台/锁屏可控），循环与随机交给 just_audio 原生处理
/// - 播放模式 / 队列 / 位置持久化，重启后恢复（不自动播放，按播放键继续）
class PlayerService {
  /// 全局唯一实例（audio_service handler 与 UI 共用）
  static final PlayerService instance = PlayerService._();

  PlayerService._() : _player = AudioPlayer() {
    // 同步当前播放下标（队列操作 / 原生切歌都会反映到这里）
    _indexSub = _player.currentIndexStream.listen((idx) {
      if (idx == null || idx == _index) return;
      _index = idx;
      // 切歌（手动跳过 / 自动连播）立刻落盘：进度只记"现在这首"，
      // 被切掉歌曲的中间进度不保留
      unawaited(_persistQueue());
      unawaited(_persistPosition());
      _notify();
    });
    // 整个队列播完：循环模式回到第一首，顺序模式停止
    _player.playerStateStream.listen((state) {
      if (state.processingState != ProcessingState.completed) return;
      if (_mode == PlayMode.sequential) {
        stop();
      } else {
        // listLoop / shuffle：回到队首继续
        _playIndex(0);
      }
    });
    // 播放位置周期性持久化（每 5 秒）
    _positionSaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _persistPosition(),
    );
    unawaited(_restore());
  }

  final AudioPlayer _player;
  final Random _random = Random();

  List<String> _queue = [];
  List<String> _titles = [];
  List<String> _covers = [];
  int _index = 0;
  PlayMode _mode = PlayMode.listLoop;
  ConcatenatingAudioSource? _playlist;

  /// 队列已恢复但尚未加载音频源；首次播放时才真正加载
  bool _restoredPending = false;
  Duration _savedPosition = Duration.zero;

  /// 任何会影响 UI 的状态变化后触发（含恢复完成）
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changeStream => _changes.stream;

  bool get playing => _player.playing;
  bool get hasQueue => _queue.isNotEmpty;
  int get index => _index;
  int get queueLength => _queue.length;
  PlayMode get mode => _mode;

  String? get currentTitle => _titles.isEmpty
      ? null
      : (_titles[_index].isEmpty ? null : _titles[_index]);
  String? get currentCover =>
      _covers.isEmpty ? null : (_covers[_index].isEmpty ? null : _covers[_index]);

  List<String> get titles => List.unmodifiable(_titles);
  List<String> get covers => List.unmodifiable(_covers);

  Stream<PlayerState> get stateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  void setMode(PlayMode mode) {
    _mode = mode;
    _applyMode();
    unawaited(_persistMode());
    _notify();
  }

  void _applyMode() {
    switch (_mode) {
      case PlayMode.listLoop:
        _player.setLoopMode(LoopMode.all);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.singleLoop:
        _player.setLoopMode(LoopMode.one);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.sequential:
        _player.setLoopMode(LoopMode.off);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.shuffle:
        _player.setLoopMode(LoopMode.off);
        _player.setShuffleModeEnabled(true);
        break;
    }
  }

  /// 播放一个 URL 队列（titles / covers 与 urls 一一对应，用于展示）
  Future<void> playQueue(
    List<String> urls, {
    List<String> titles = const [],
    List<String> covers = const [],
    int startIndex = 0,
  }) async {
    _queue = urls;
    _titles = titles.length == urls.length
        ? titles
        : List.filled(urls.length, '');
    _covers = covers.length == urls.length
        ? covers
        : List.filled(urls.length, '');
    _index = startIndex.clamp(0, urls.length - 1);
    // 新队列一律从头播：不携带重启恢复出的旧进度
    _savedPosition = Duration.zero;
    await _buildAndLoad(_index, autoplay: true);
    unawaited(_persistQueue());
    _notify();
  }

  /// 播放单个 URL
  Future<void> playUrl(String url, {String? title, String? cover}) async {
    _queue = [url];
    _titles = [title ?? ''];
    _covers = [cover ?? ''];
    _index = 0;
    _savedPosition = Duration.zero;
    await _buildAndLoad(0, autoplay: true);
    unawaited(_persistQueue());
    _notify();
  }

  /// 构建队列源并加载（通知栏 tag 逐首携带，懒加载不预下载）
  Future<void> _buildAndLoad(int startIndex, {required bool autoplay}) async {
    if (_queue.isEmpty) return;
    _playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: [
        for (var i = 0; i < _queue.length; i++)
          AudioSource.uri(
            Uri.parse(_queue[i]),
            tag: MediaItem(
              id: _queue[i],
              album: 'QQ 音乐',
              title: _titles[i].isEmpty ? '未知歌曲' : _titles[i],
              artUri: _covers[i].isEmpty ? null : Uri.tryParse(_covers[i]),
            ),
          ),
      ],
    );
    _index = startIndex;
    _restoredPending = false;
    await _player.setAudioSource(
      _playlist!,
      initialIndex: startIndex,
      initialPosition: _savedPosition,
    );
    _applyMode();
    if (autoplay) {
      _player.play();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    unawaited(_persistPosition());
  }

  Future<void> resume() async {
    // 恢复的队列尚未加载音频源（vkey 链接有时效，过期则失败）
    if (_restoredPending && _queue.isNotEmpty) {
      await _buildAndLoad(_index, autoplay: true);
      // 恢复出的进度只在这一步使用一次
      _savedPosition = Duration.zero;
      return;
    }
    _player.play();
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    unawaited(_persistPosition());
  }

  /// 拖动进度
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    unawaited(_persistPosition());
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    switch (_mode) {
      case PlayMode.shuffle:
        if (_queue.length > 1) {
          var n = _index;
          while (n == _index) {
            n = _random.nextInt(_queue.length);
          }
          await _playIndex(n);
        }
        break;
      case PlayMode.listLoop:
        if (_index < _queue.length - 1) {
          await _player.seekToNext();
        } else {
          await _playIndex(0);
        }
        break;
      case PlayMode.singleLoop:
      case PlayMode.sequential:
        if (_index < _queue.length - 1) {
          await _player.seekToNext();
        } else {
          await stop();
        }
        break;
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_index > 0) {
      await _player.seekToPrevious();
    } else if (_mode == PlayMode.listLoop) {
      await _playIndex(_queue.length - 1);
    }
  }

  /// 播放队列中的第 [i] 首（播放列表点选）
  Future<void> playIndex(int i) async => _playIndex(i);

  Future<void> _playIndex(int i) async {
    if (i < 0 || i >= _queue.length || _playlist == null) return;
    await _player.seek(Duration.zero, index: i);
    _index = i;
    _player.play();
    unawaited(_persistQueue());
    _notify();
  }

  /// 从队列移除第 [i] 首；移除的是当前播放歌曲时自动播下一首
  Future<void> removeFromQueue(int i) async {
    if (i < 0 || i >= _queue.length) return;
    final wasCurrent = i == _index;
    _queue.removeAt(i);
    _titles.removeAt(i);
    _covers.removeAt(i);
    if (_queue.isEmpty) {
      await clear();
      return;
    }
    try {
      await _playlist?.removeAt(i);
    } catch (_) {}
    if (wasCurrent) {
      if (_index >= _queue.length) _index = _queue.length - 1;
      _player.play();
    } else if (i < _index) {
      _index--;
    }
    unawaited(_persistQueue());
    _notify();
  }

  /// 清空队列并停止播放
  Future<void> clear() async {
    _queue = [];
    _titles = [];
    _covers = [];
    _index = 0;
    _playlist = null;
    _restoredPending = false;
    _savedPosition = Duration.zero;
    await stop();
    unawaited(_persistQueue());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('player_position');
    _notify();
  }

  void _notify() => _changes.add(null);

  // ---------- 持久化 ----------

  Future<void> _persistMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('player_mode', _mode.index);
  }

  Future<void> _persistQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('player_queue', _queue);
    await prefs.setStringList('player_titles', _titles);
    await prefs.setStringList('player_covers', _covers);
    await prefs.setInt('player_index', _index);
  }

  Future<void> _persistPosition() async {
    if (_queue.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('player_position', _player.position.inMilliseconds);
  }

  /// 启动时恢复：模式 / 队列 / 位置（不自动播放，不立即加载网络流）
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIdx = prefs.getInt('player_mode');
      if (modeIdx != null && modeIdx >= 0 && modeIdx < PlayMode.values.length) {
        _mode = PlayMode.values[modeIdx];
      }
      final urls = prefs.getStringList('player_queue') ?? [];
      if (urls.isNotEmpty) {
        _queue = urls;
        _titles =
            prefs.getStringList('player_titles') ?? List.filled(urls.length, '');
        _covers = prefs.getStringList('player_covers') ??
            List.filled(urls.length, '');
        if (_titles.length != urls.length) {
          _titles = List.filled(urls.length, '');
        }
        if (_covers.length != urls.length) {
          _covers = List.filled(urls.length, '');
        }
        final idx = prefs.getInt('player_index') ?? 0;
        _index = idx.clamp(0, urls.length - 1);
        _savedPosition =
            Duration(milliseconds: prefs.getInt('player_position') ?? 0);
        _restoredPending = true;
      }
    } catch (_) {
      // 恢复失败不影响使用
    } finally {
      _notify();
    }
  }

  Future<void> dispose() async {
    _positionSaveTimer?.cancel();
    _indexSub?.cancel();
    await _player.dispose();
  }

  Timer? _positionSaveTimer;
  StreamSubscription<int?>? _indexSub;
}
