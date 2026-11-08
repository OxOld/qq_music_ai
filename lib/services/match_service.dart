import '../models/playlist.dart';
import '../models/qq_song.dart';
import 'qq_music_client.dart';

/// 匹配结果：AI 歌单中的一首歌 → 搜索匹配到的 QQ 音乐歌曲
class MatchResult {
  final Song original;
  final QQSong? matched;

  const MatchResult({required this.original, this.matched});

  bool get isMatched => matched != null;
}

/// 搜索被临时限流的异常（终止整次匹配，给出明确提示）
class MatchRateLimitException implements Exception {
  final String message;
  MatchRateLimitException(this.message);

  @override
  String toString() => message;
}

/// 进度回调：index = 歌曲下标；result 为 null 表示该首开始匹配
typedef MatchProgressCallback = void Function(int index, MatchResult? result);

/// 把 AI 生成的歌单（歌名+歌手）匹配成 QQ 音乐真实歌曲
class MatchService {
  MatchService({QQMusicClient? client}) : _client = client ?? QQMusicClient();

  final QQMusicClient _client;

  /// 连续网络失败达到该次数即判定为被限流，终止本次匹配
  static const _maxConsecutiveFailures = 3;

  /// 连续空结果达到该次数，判定为限流（真实歌单极少连续 3 首都不在曲库）
  static const _maxEmptyStreak = 3;

  /// 每次搜索之间的间隔（避免触发频控）
  static const _throttle = Duration(milliseconds: 800);

  /// 逐首搜索匹配，返回匹配结果列表。[onProgress] 实时上报每首状态
  Future<List<MatchResult>> matchPlaylist(
    Playlist playlist, {
    QQAuthState? auth,
    MatchProgressCallback? onProgress,
  }) {
    return matchSongs(playlist.songs, auth: auth, onProgress: onProgress);
  }

  /// 匹配任意一组歌曲（歌单详情页的 AI 补充等场景复用节流/重试/限流判定）
  Future<List<MatchResult>> matchSongs(
    List<Song> songs, {
    QQAuthState? auth,
    MatchProgressCallback? onProgress,
  }) async {
    final results = <MatchResult>[];
    var consecutiveFailures = 0;
    var emptyStreak = 0;

    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      onProgress?.call(i, null); // 该首开始匹配
      if (results.isNotEmpty) {
        await Future.delayed(_throttle);
      }

      MatchResult result;
      try {
        result = await _searchWithRetry(song, auth);
        consecutiveFailures = 0;
      } catch (e) {
        consecutiveFailures++;
        // 与网络相关的失败才计入限流判定；正常无结果不算
        if (consecutiveFailures >= _maxConsecutiveFailures) {
          throw MatchRateLimitException(
            '曲库搜索连续失败 $consecutiveFailures 次，疑似触发临时限流。\n'
            '请等 1-2 分钟再重新匹配（已匹配部分不受影响）。',
          );
        }
        onProgress?.call(i, null);
        results.add(MatchResult(original: song, matched: null));
        continue;
      }

      // 连续空结果 = 大概率被限流返回了空列表
      if (result.matched == null) {
        emptyStreak++;
        if (emptyStreak >= _maxEmptyStreak) {
          throw MatchRateLimitException(
            '连续 $emptyStreak 首搜索无结果，疑似被临时限流'
            '（这几首在曲库中其实是存在的）。\n'
            '请等 1-2 分钟后重新匹配；保持登录状态会更稳定。',
          );
        }
      } else {
        emptyStreak = 0;
      }
      onProgress?.call(i, result);
      results.add(result);
    }
    return results;
  }

  /// 搜索单首歌，网络异常自动重试（退避 1s / 2.5s）
  Future<MatchResult> _searchWithRetry(Song song, QQAuthState? auth) async {
    final keyword = '${song.name} ${song.artist}'.trim();
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final candidates = await _client.search(keyword, limit: 5, auth: auth);
        return MatchResult(
          original: song,
          matched: _pickBest(song, candidates),
        );
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          await Future.delayed(
            Duration(milliseconds: attempt == 0 ? 1000 : 2500),
          );
        }
      }
    }
    throw lastError ?? Exception('搜索失败');
  }

  /// 从候选里挑最匹配的一首（歌名 + 歌手相似度打分）
  QQSong? _pickBest(Song song, List<QQSong> candidates) {
    if (candidates.isEmpty) return null;
    QQSong? best;
    var bestScore = 0.0;
    for (final c in candidates) {
      final score =
          _similarity(song.name, c.name) * 0.7 +
          _similarity(song.artist, c.artist) * 0.3;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return bestScore > 0.3 ? best : null;
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final la = a.toLowerCase().replaceAll(' ', '');
    final lb = b.toLowerCase().replaceAll(' ', '');
    if (la == lb) return 1.0;
    if (la.contains(lb) || lb.contains(la)) return 0.9;
    return 0.5;
  }
}
