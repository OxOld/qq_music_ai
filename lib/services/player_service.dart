import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放模式
enum PlayMode { listLoop, singleLoop, sequential, shuffle }

/// 恢复队列换链接的结果
class UrlRefreshResult {
  /// 与传入 mids 等长：换到新链接的下标为新 URL，失败为 null
  final List<String?> urls;

  /// true = 换链接时发现登录态过期（UI 应引导重新登录）
  final bool authExpired;

  const UrlRefreshResult(this.urls, {this.authExpired = false});
}

/// 恢复队列播放前的批量换链接回调（main 里注入，本服务不依赖登录态）
typedef UrlRefresher = Future<UrlRefreshResult?> Function(List<String> mids);

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
  List<String> _mids = [];
  List<String> _titles = [];
  List<String> _covers = [];
  int _index = 0;
  PlayMode _mode = PlayMode.listLoop;
  ConcatenatingAudioSource? _playlist;

  /// 队列已恢复但尚未加载音频源；首次播放时才真正加载
  bool _restoredPending = false;
  Duration _savedPosition = Duration.zero;

  /// 恢复队列播放前换新链接的回调（vkey 链接数小时即失效，
  /// 持久化的旧链接直接播会失败）；main 里注入，默认空 = 旧行为
  UrlRefresher? urlRefresher;

  /// 队列链接的保守有效期：vkey 链接约数小时失效，超过 3 小时即视为过期
  static const _urlMaxAge = Duration(hours: 3);

  /// 队列链接最近一次获取/确认的时间（随队列持久化）
  DateTime? _urlsFetchedAt;

  /// 播放准备（换链接 + 重建队列源）的并发锁：多个入口同时点只做一次
  Future<bool>? _prepareFuture;

  /// 正在换新链接（UI 可显示等待状态）
  bool _restoring = false;

  /// 上一次换链接时是否发现登录态过期（UI 读后引导重登）
  bool _lastRefreshAuthExpired = false;

  /// 队列代次：换新队列 / 增删曲目时自增。换链接是异步的，回来时如果
  /// 队列已被替换，旧结果必须整体丢弃——否则旧队列的链接会写进新队列、
  /// 旧队列的「登录过期」也会误置到能正常播放的新队列上（反复弹重登）。
  int _queueGeneration = 0;

  /// 队列链接是否已过期（缺失时间视为过期，保守处理）
  bool get _urlsStale =>
      _urlsFetchedAt == null ||
      DateTime.now().difference(_urlsFetchedAt!) > _urlMaxAge;

  /// 任何会影响 UI 的状态变化后触发（含恢复完成）
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changeStream => _changes.stream;

  bool get playing => _player.playing;
  bool get hasQueue => _queue.isNotEmpty;
  int get index => _index;
  int get queueLength => _queue.length;
  PlayMode get mode => _mode;

  /// 正在换新链接（UI 显示等待状态）
  bool get restoring => _restoring;

  /// 上一次换链接时是否发现登录态过期（UI 读后引导重登）
  bool get lastRefreshAuthExpired => _lastRefreshAuthExpired;

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

  /// 播放一个 URL 队列（mids / titles / covers 与 urls 一一对应：
  /// mid 用于恢复播放时换新链接，titles / covers 用于展示）
  Future<void> playQueue(
    List<String> urls, {
    List<String> mids = const [],
    List<String> titles = const [],
    List<String> covers = const [],
    int startIndex = 0,
  }) async {
    _queueGeneration++;
    _queue = urls;
    _mids = mids.length == urls.length ? mids : List.filled(urls.length, '');
    _titles = titles.length == urls.length
        ? titles
        : List.filled(urls.length, '');
    _covers = covers.length == urls.length
        ? covers
        : List.filled(urls.length, '');
    _index = startIndex.clamp(0, urls.length - 1);
    // 新队列一律从头播：不携带重启恢复出的旧进度
    _savedPosition = Duration.zero;
    // 刚取到的链接，记下确认时间；能取到链接说明登录态有效，
    // 顺带清掉历史误报的过期标记（否则暂停/播放会一直弹重登）
    _urlsFetchedAt = DateTime.now();
    _lastRefreshAuthExpired = false;
    await _buildAndLoad(_index, autoplay: true);
    unawaited(_persistQueue());
    _notify();
  }

  /// 播放单个 URL
  Future<void> playUrl(
    String url, {
    String? mid,
    String? title,
    String? cover,
  }) async {
    _queueGeneration++;
    _queue = [url];
    _mids = [mid ?? ''];
    _titles = [title ?? ''];
    _covers = [cover ?? ''];
    _index = 0;
    _savedPosition = Duration.zero;
    _urlsFetchedAt = DateTime.now();
    _lastRefreshAuthExpired = false;
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
    if (_queue.isEmpty) return;
    if (!await _prepareForPlayback()) return;
    _player.play();
  }

  /// 任何播放操作前的统一准备（播放键 / 播放列表点选 / 上一首 / 下一首）：
  /// - 恢复的队列尚未加载音频源 → 先加载
  /// - 队列链接已过期（间隔数小时/数天再点）→ 换新链接并重建队列源
  /// 并发调用共享同一次准备，避免并发 setAudioSource。
  Future<bool> _prepareForPlayback() {
    final existing = _prepareFuture;
    if (existing != null) return existing;
    final f = _doPrepareForPlayback();
    _prepareFuture = f;
    f.whenComplete(() {
      if (identical(_prepareFuture, f)) _prepareFuture = null;
    });
    return f;
  }

  Future<bool> _doPrepareForPlayback() async {
    if (_queue.isEmpty) return false;
    final gen = _queueGeneration;
    try {
      final restored = _restoredPending;
      // 运行态且链接新鲜：队列源已就绪，直接播
      if (!restored && _playlist != null && !_urlsStale) return true;
      if (_urlsStale) {
        await _refreshQueueUrls();
        // 换链期间用户换了歌单/增删曲目：交给新队列自己的流程
        if (gen != _queueGeneration) return _playlist != null;
      }
      if (gen != _queueGeneration) return _playlist != null;
      // 重建队列源：恢复态沿用持久化进度，运行态沿用当前播放位置
      if (!restored) _savedPosition = _player.position;
      await _buildAndLoad(_index, autoplay: false);
      _savedPosition = Duration.zero;
      return _playlist != null;
    } catch (e) {
      // 准备失败（如并发加载冲突）不抛出：保持队列源原状，
      // 由后续播放失败暴露问题，避免依赖它的 UI 操作被中断
      debugPrint('[diag] prepare playback failed: $e');
      return _playlist != null;
    }
  }

  /// 把队列里的旧 vkey 链接批量换成新的。
  /// 回调未注入 / 队列无 mid（旧版本持久化的数据）/ 回调失败时，
  /// 保留旧链接按原行为播放（可能播不了，与旧行为一致）。
  Future<void> _refreshQueueUrls() async {
    final refresher = urlRefresher;
    if (refresher == null) return;
    final hasMids =
        _mids.length == _queue.length && _mids.any((m) => m.isNotEmpty);
    if (!hasMids) {
      // 旧版本持久化的队列没有 mid，本来就换不了链接：记为已确认，
      // 避免每次点播放都重建一次音频源（链接救不回来，与旧行为一致）
      _urlsFetchedAt = DateTime.now();
      return;
    }
    // 快照：换链接期间用户可能增删队列，回调不应看到被改动的列表
    final mids = List<String>.of(_mids);
    final gen = _queueGeneration;
    _restoring = true;
    _lastRefreshAuthExpired = false;
    _notify();
    try {
      final result = await refresher(mids);
      // 等接口期间队列已被替换/增删：结果属于旧队列，整体丢弃
      if (result == null || gen != _queueGeneration) return;
      var changed = 0;
      var refreshed = 0;
      for (var i = 0; i < _queue.length && i < result.urls.length; i++) {
        final u = result.urls[i];
        if (u == null || u.isEmpty) continue;
        refreshed++;
        if (u != _queue[i]) {
          _queue[i] = u;
          changed++;
        }
      }
      // 兜底：只要换到了链接就说明登录态有效，单曲失败不算过期
      _lastRefreshAuthExpired = result.authExpired && refreshed == 0;
      // 一首都没换到时（登录过期/网络失败）不记确认时间，下次播放再试
      if (refreshed > 0) {
        _urlsFetchedAt = DateTime.now();
      }
      debugPrint(
        '[diag] queue urls refreshed total=${_queue.length} changed=$changed '
        'refreshed=$refreshed authExpired=$_lastRefreshAuthExpired',
      );
      // 新链接落盘，下次恢复直接可用
      unawaited(_persistQueue());
    } catch (_) {
      // 换链接失败不影响原流程：保留旧链接尝试播放
    } finally {
      _restoring = false;
      _notify();
    }
  }

  /// 清除「上次换链接发现登录过期」标记。
  /// UI 弹过一次重登提示后调用，避免用户在暂停/播放之间反复看到同一提示；
  /// 下次换链接仍然失败会重新置位。
  void acknowledgeAuthExpired() {
    if (!_lastRefreshAuthExpired) return;
    _lastRefreshAuthExpired = false;
    _notify();
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
    if (!await _prepareForPlayback()) return;
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
    if (!await _prepareForPlayback()) return;
    if (_index > 0) {
      await _player.seekToPrevious();
    } else if (_mode == PlayMode.listLoop) {
      await _playIndex(_queue.length - 1);
    }
  }

  /// 播放队列中的第 [i] 首（播放列表点选）
  Future<void> playIndex(int i) async => _playIndex(i);

  Future<void> _playIndex(int i) async {
    if (i < 0 || i >= _queue.length) return;
    // 播放列表点选同样要准备：冷启动恢复的队列此时尚未加载
    if (!await _prepareForPlayback()) return;
    await _player.seek(Duration.zero, index: i);
    _index = i;
    _player.play();
    unawaited(_persistQueue());
    _notify();
  }

  /// 从队列移除第 [i] 首；移除的是当前播放歌曲时自动播下一首
  Future<void> removeFromQueue(int i) async {
    if (i < 0 || i >= _queue.length) return;
    _queueGeneration++;
    final wasCurrent = i == _index;
    _queue.removeAt(i);
    if (_mids.length == _queue.length + 1) _mids.removeAt(i);
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
    _queueGeneration++;
    _queue = [];
    _mids = [];
    _titles = [];
    _covers = [];
    _index = 0;
    _playlist = null;
    _restoredPending = false;
    _urlsFetchedAt = null;
    _lastRefreshAuthExpired = false;
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
    await prefs.setStringList('player_mids', _mids);
    await prefs.setStringList('player_titles', _titles);
    await prefs.setStringList('player_covers', _covers);
    await prefs.setInt('player_index', _index);
    await prefs.setInt(
      'player_urls_ts',
      _urlsFetchedAt?.millisecondsSinceEpoch ?? 0,
    );
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
        _mids = prefs.getStringList('player_mids') ??
            List.filled(urls.length, '');
        _titles =
            prefs.getStringList('player_titles') ?? List.filled(urls.length, '');
        _covers = prefs.getStringList('player_covers') ??
            List.filled(urls.length, '');
        if (_mids.length != urls.length) {
          _mids = List.filled(urls.length, '');
        }
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
        final ts = prefs.getInt('player_urls_ts') ?? 0;
        _urlsFetchedAt =
            ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
        _restoredPending = true;
        // 启动即预加载恢复队列（换新链接 + 加载音频源，不播放）：
        // 1) 媒体会话进入 ready 并激活——车机方控/方向盘媒体键只会路由
        //    给 active 的 MediaSession（冷启动未播放时原实现不激活，
        //    表现为「车机启动后方向盘控制失效」，见 audio_service 补丁）；
        // 2) 方向盘「播放」键由 just_audio_background 直接驱动底层播放器，
        //    源已就绪、链接已刷新，按下即可出声。
        unawaited(_prepareForPlayback());
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
