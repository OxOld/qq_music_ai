import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/qq_song.dart';
import '../providers/providers.dart';
import '../services/battery_service.dart';
import '../services/qq_music_client.dart';
import '../theme/app_theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_toast.dart';
import '../widgets/mini_player.dart';
import '../widgets/relogin_dialog.dart';
import '../widgets/song_manage_sheet.dart';
import 'login_page.dart';

/// 歌单详情：歌曲列表 + 单曲播放 + 播放全部
class PlaylistDetailPage extends ConsumerStatefulWidget {
  final MyPlaylist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  List<QQSong>? _songs;
  bool _loading = false;
  String? _error;
  int? _preparingIndex; // 正在预取播放链接的行
  String _query = ''; // 搜索框过滤

  /// 搜索过滤后的可见歌曲
  List<QQSong> get _visibleSongs {
    final songs = _songs ?? const <QQSong>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return songs;
    return songs
        .where(
          (s) =>
              s.name.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q),
        )
        .toList();
  }

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
      final client = ref.read(qqMusicClientProvider);
      var songs = await client.getPlaylistSongs(auth, widget.playlist.id);
      // 歌单应有多首却只返回 1 首：登录态降级时服务端的兜底表现，
      // 静默续期后重试一次，仍不符则提示用户重登
      if (songs.length == 1 && widget.playlist.count > 1) {
        debugPrint(
          '[diag] CgiGetDiss tid=${widget.playlist.id} '
          'expect=${widget.playlist.count} got=1 -> refresh & retry',
        );
        await ref.read(qqAuthProvider.notifier).refresh();
        songs = await ref
            .read(qqMusicClientProvider)
            .getPlaylistSongs(ref.read(qqAuthProvider), widget.playlist.id);
        if (!mounted) return;
        if (songs.length == 1 && widget.playlist.count > 1) {
          AppToast.show(
            context,
            '仅获取到 1/${widget.playlist.count} 首，登录态可能已过期，建议重新登录',
            error: true,
          );
        }
      }
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
  /// 返回 (urls, mids, titles, covers, 原下标->队列下标映射)
  Future<(List<String>, List<String>, List<String>, List<String>, List<int>)>
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
    final outMids = <String>[];
    final outTitles = <String>[];
    final outCovers = <String>[];
    final indexMap = <int>[]; // 原下标 -> 队列下标
    for (var i = 0; i < songs.length; i++) {
      final u = urls[i];
      if (u == null) continue;
      indexMap.add(outUrls.length);
      outUrls.add(u);
      outMids.add(songs[i].mid);
      outTitles.add(songs[i].name);
      outCovers.add(songs[i].coverUrl ?? '');
    }
    return (outUrls, outMids, outTitles, outCovers, indexMap);
  }

  /// 播放链接预取 + 登录态自愈。
  ///
  /// 「塌缩」是多首歌单只取到 ≤1 条链接：登录态过期后逐首取链接全部失败，
  /// 仅剩 URL 缓存里 60 分钟内取过的旧链接，队列就只剩那一首——表现为
  /// 「无论点哪个歌单都播出同一首歌」。此时静默续期登录态后重试一次。
  Future<(List<String>, List<String>, List<String>, List<String>, List<int>)>
  _prepareQueueWithRecovery(List<QQSong> songs) async {
    var result = await _prepareQueue(songs);
    final collapsed = songs.length > 1 && result.$4.length <= 1;
    if (result.$4.isEmpty || collapsed) {
      debugPrint(
        '[diag] prepareQueue songs=${songs.length} ok=${result.$4.length} '
        '-> refresh & retry',
      );
      await ref.read(qqAuthProvider.notifier).refresh();
      result = await _prepareQueue(songs);
    }
    return result;
  }

  /// 点击某一首（[index] 非 null，整单入队从该首开始播）或全部播放
  Future<void> _startPlayback(int? index) async {
    final songs = _songs;
    if (songs == null || songs.isEmpty || (index != null && index >= songs.length)) {
      return;
    }
    if (_preparingIndex != null) return;
    unawaited(BatteryService.maybePromptOnPlay(context));
    setState(() => _preparingIndex = index ?? 0);
    try {
      final (urls, mids, titles, covers, indexMap) =
          await _prepareQueueWithRecovery(songs);
      if (!mounted) return;
      if (indexMap.isEmpty) {
        // 全部失败：实测登录态过期时所有歌的 purl 都是空的，引导重登
        final relogin = await showAppConfirmDialog(
          context,
          title: '登录已过期',
          message: '所有歌曲都取不到播放链接。\n重新扫码登录后即可恢复播放。',
          confirmLabel: '重新登录',
          icon: Icons.login_rounded,
        );
        if (relogin && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        }
        return;
      }
      if (songs.length > 1 && indexMap.length <= 1) {
        // 续期重试后仍只拿到 1 首：明确告知，而不是默默只播这一首
        final relogin = await showAppConfirmDialog(
          context,
          title: '播放链接获取不全',
          message:
              '歌单 ${songs.length} 首中仅获取到 ${indexMap.length} 首的播放链接，'
              '登录态可能已过期。重新扫码登录后通常可恢复。',
          confirmLabel: '重新登录',
          cancelLabel: '仍播放这 ${indexMap.length} 首',
          icon: Icons.login_rounded,
        );
        if (relogin && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
          return;
        }
      }
      final startIndex = index == null
          ? indexMap.first
          : (index < indexMap.length ? indexMap[index] : indexMap.first);
      await ref
          .read(playerServiceProvider)
          .playQueue(
            urls,
            mids: mids,
            titles: titles,
            covers: covers,
            startIndex: startIndex.clamp(0, urls.length - 1),
          );
    } finally {
      if (mounted) setState(() => _preparingIndex = null);
    }
  }

  /// 移除单首歌（自建歌单）：确认后调用 DelSonglist，成功后做局部刷新
  Future<void> _removeSong(QQSong song) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '移除歌曲',
      message: '确定把「${song.name}」从歌单移除吗？',
      confirmLabel: '移除',
      danger: true,
      icon: Icons.playlist_remove_rounded,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(qqAuthProvider.notifier).runWithFreshAuth((auth) async {
        return ref.read(qqMusicClientProvider).removeSongsFromPlaylist(
          auth,
          widget.playlist.dirId,
          [song],
        );
      });
      if (!mounted) return;
      // 局部刷新：服务端已删成功，本地直接移除这一首即可。
      // 不做整页重载，避免列表重建后滚动位置丢失（删中间的歌还要重新往下翻）
      setState(() {
        _songs = _songs
            ?.where((s) => !(s.songId == song.songId && s.mid == song.mid))
            .toList();
      });
      AppToast.show(context, '已移除「${song.name}」', success: true);
    } on QQMusicAuthExpiredException {
      if (!mounted) return;
      await showReloginDialog(context);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '移除失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.playlist;
    final canManage = p.isCreated && p.dirId > 0;
    final visible = _visibleSongs;

    // 状态栏白色图标（顶部为品牌渐变）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusOverlayLight,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        // 播放状态贯穿：详情页底部同样显示迷你播放条
        bottomNavigationBar: MiniPlayer(),
        body: Column(
          children: [
            // ---------- 头部：大封面 + 标题 ----------
            Container(
              decoration: BoxDecoration(gradient: AppColors.brandGradient),
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 18),
              child: SafeArea(
                bottom: false,
                // 车机全屏投屏时系统可能不提供状态栏内边距，补最小顶部留白避免封面贴顶
                minimum: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 78,
                        height: 78,
                        color: Colors.white.withValues(alpha: 0.2),
                        child: p.coverUrl != null
                            ? Image.network(
                                p.coverUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.queue_music_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              )
                            : const Icon(
                                Icons.queue_music_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            // 有实时列表时以列表为准（AI 补充/移除后立即反映）
                            '${_songs?.length ?? p.count} 首',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ---------- 底部白色圆角内容区（搜索 / 全部播放 / 列表） ----------
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    // 搜索框：灰底内嵌，与设置页输入框同款
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: '搜索歌曲',
                          filled: true,
                          fillColor: AppColors.bg,
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : GestureDetector(
                                  onTap: () => setState(() => _query = ''),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppColors.brand,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 全部播放 + AI 补充
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                                onTap: (_songs == null || _songs!.isEmpty)
                                    ? null
                                    : () => _startPlayback(null),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.play_circle_fill_rounded,
                                      size: 26,
                                      color: AppColors.brand,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '全部播放(${_songs?.length ?? p.count})',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (canManage)
                            Material(
                              color: AppColors.brandSoft,
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: _songs == null
                                    ? null
                                    : () => showSongManageSheet(
                                        context,
                                        playlist: p,
                                        currentSongs: _songs!,
                                        onChanged: _load,
                                      ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 15,
                                        color: AppColors.brandDeep,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'AI 补充',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.brandDeep,
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
                    // ---------- 歌曲列表（编号样式，点击整行播放） ----------
                    Expanded(child: _buildSongList(visible, canManage)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongList(List<QQSong> visible, bool canManage) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
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
              style: const TextStyle(color: Color(0xFFB0333E), fontSize: 13),
            ),
          ),
        ],
      );
    }
    if (_songs == null || _songs!.isEmpty) {
      return const Center(
        child: Text(
          '歌单是空的',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          '没有匹配「$_query」的歌曲',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final s = visible[i];
        final orig = _songs!.indexWhere(
          (e) => e.songId == s.songId && e.mid == s.mid,
        );
        final player = ref.read(playerServiceProvider);
        final playing = player.currentTitle == s.name && player.hasQueue;
        final preparing = _preparingIndex == orig;
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: orig >= 0 ? () => _startPlayback(orig) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    height: 24,
                    child: Center(
                      child: preparing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '${orig + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: playing
                                    ? AppColors.brandDeep
                                    : AppColors.textSecondary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: playing
                                ? AppColors.brandDeep
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canManage)
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _removeSong(s),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.remove_circle_outline_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
