import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/qq_song.dart';
import '../providers/providers.dart';
import '../services/qq_music_client.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/mini_player.dart';

/// 歌单详情：歌曲列表 + 单曲播放 + 播放全部
class PlaylistDetailPage extends ConsumerStatefulWidget {
  final MyPlaylist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailPage> createState() =>
      _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  List<QQSong>? _songs;
  bool _loading = false;
  final bool _playingAll = false;
  String? _error;
  int? _preparingIndex; // 正在预取播放链接的行

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(qqAuthProvider);
    if (!auth.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await ref
          .read(qqMusicClientProvider)
          .getPlaylistSongs(auth, widget.playlist.id);
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 预取整个歌单的播放链接（3 路并行；本地缓存命中的瞬间返回）
  /// 返回 (urls, titles, covers, 原下标->队列下标映射)
  Future<(List<String>, List<String>, List<String>, List<int>)>
      _prepareQueue(List<QQSong> songs) async {
    final auth = ref.read(qqAuthProvider);
    final client = ref.read(qqMusicClientProvider);
    final urls = List<String?>.filled(songs.length, null);
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < songs.length) {
        final i = cursor++;
        try {
          urls[i] = await client.getPlayUrl(auth, songs[i].mid);
        } catch (_) {}
      }
    }

    await Future.wait([worker(), worker(), worker()]);

    final outUrls = <String>[];
    final outTitles = <String>[];
    final outCovers = <String>[];
    final indexMap = <int>[]; // 原下标 -> 队列下标
    for (var i = 0; i < songs.length; i++) {
      final u = urls[i];
      if (u == null) continue;
      indexMap.add(outUrls.length);
      outUrls.add(u);
      outTitles.add(songs[i].name);
      outCovers.add(songs[i].coverUrl ?? '');
    }
    return (outUrls, outTitles, outCovers, indexMap);
  }

  /// 点击某一首：整个歌单入队，从该首开始播放
  Future<void> _play(int index) async {
    final songs = _songs;
    if (songs == null || songs.isEmpty || index >= songs.length) return;
    if (_preparingIndex != null) return;
    setState(() => _preparingIndex = index);
    try {
      final (urls, titles, covers, indexMap) = await _prepareQueue(songs);
      if (!mounted) return;
      if (indexMap.isEmpty) {
        AppToast.show(context, '没有可播放的歌曲（可能都是会员歌曲）', error: true);
        return;
      }
      final startIndex =
          index < indexMap.length ? indexMap[index] : indexMap.first;
      await ref
          .read(playerServiceProvider)
          .playQueue(urls,
              titles: titles,
              covers: covers,
              startIndex: startIndex.clamp(0, urls.length - 1));
    } finally {
      if (mounted) setState(() => _preparingIndex = null);
    }
  }

  Future<void> _playAll() async {
    final songs = _songs;
    if (songs == null || songs.isEmpty) return;
    if (_preparingIndex != null) return;
    setState(() => _preparingIndex = 0);
    try {
      final (urls, titles, covers, indexMap) = await _prepareQueue(songs);
      if (!mounted) return;
      if (indexMap.isEmpty) {
        AppToast.show(context, '没有可播放的歌曲（可能都是会员歌曲）', error: true);
        return;
      }
      await ref
          .read(playerServiceProvider)
          .playQueue(urls,
              titles: titles,
              covers: covers,
              startIndex: indexMap.first.clamp(0, urls.length - 1));
    } finally {
      if (mounted) setState(() => _preparingIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.playlist;
    return Scaffold(
      backgroundColor: AppColors.bg,
      // 播放状态贯穿：详情页底部同样显示迷你播放条
      bottomNavigationBar: const MiniPlayer(),
      body: Column(
        children: [
          // ---------- 固定头部 ----------
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 0, 20, 20),
            child: SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 52,
                      height: 52,
                      color: Colors.white.withValues(alpha: 0.2),
                      child: p.coverUrl != null
                          ? Image.network(
                              p.coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                  Icons.queue_music_rounded,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.queue_music_rounded,
                              color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${p.count} 首',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 播放全部
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _playingAll ? null : _playAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          children: [
                            if (_playingAll)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            else
                              Icon(Icons.play_arrow_rounded,
                                  size: 19, color: AppColors.brandDeep),
                            const SizedBox(width: 4),
                            Text(
                              '播放全部',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _playingAll
                                    ? AppColors.textSecondary
                                    : AppColors.brandDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ---------- 歌曲列表 ----------
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.dangerSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Color(0xFFB0333E), fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    : _songs == null || _songs!.isEmpty
                        ? const Center(
                            child: Text('歌单是空的',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13.5)),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: _songs!.length,
                            itemBuilder: (context, i) {
                              final s = _songs![i];
                              final service = ref.read(playerServiceProvider);
                              final playing =
                                  service.currentTitle == s.name &&
                                      service.hasQueue;
                              final preparing = _preparingIndex == i;
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.fromLTRB(
                                    10, 6, 6, 6),
                                decoration: BoxDecoration(
                                  color: playing
                                      ? AppColors.brandSoft
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0x0D1C2420),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: Container(
                                        width: 42,
                                        height: 42,
                                        color: AppColors.brandSoft,
                                        child: s.coverUrl != null
                                            ? Image.network(
                                                s.coverUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (_, _, _) =>
                                                        Icon(
                                                  Icons
                                                      .music_note_rounded,
                                                  size: 20,
                                                  color: AppColors
                                                      .brandDeep,
                                                ),
                                              )
                                            : Icon(
                                                Icons.music_note_rounded,
                                                size: 20,
                                                color:
                                                    AppColors.brandDeep,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.name,
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: playing
                                                  ? AppColors.brandDeep
                                                  : AppColors
                                                      .textPrimary,
                                            ),
                                          ),
                                          Text(
                                            s.artist,
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color:
                                                  AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    preparing
                                        ? const Padding(
                                            padding: EdgeInsets.all(8),
                                            child: SizedBox(
                                              width: 17,
                                              height: 17,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          )
                                        : Material(
                                            color: playing
                                                ? Colors.white
                                                : AppColors.brandSoft,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              onTap: () => _play(i),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                child: Icon(
                                                  playing
                                                      ? Icons
                                                          .graphic_eq_rounded
                                                      : Icons
                                                          .play_arrow_rounded,
                                                  size: 22,
                                                  color: AppColors.brandDeep,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ],
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
