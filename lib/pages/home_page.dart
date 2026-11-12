import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../models/qq_song.dart';
import '../providers/providers.dart';
import '../services/battery_service.dart';
import '../services/match_service.dart';
import '../services/qq_music_client.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'login_page.dart';
import 'settings_page.dart';

/// 首页：顶部固定头部，下方滚动内容
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController(); // 匹配完成后自动露出底部按钮

  bool _loading = false;
  Playlist? _playlist;
  List<MatchResult>? _matchResults;
  List<MatchResult?>? _matchProgress; // 匹配中的逐首状态（null=未匹配到该首）
  bool _matching = false;
  bool _creating = false;
  String? _loadingPlayMid; // 正在获取播放链接的歌（行内转圈）
  bool _playAllLoading = false; // 播放全部：预取链接中
  String? _error;

  static const _examples = [
    '深夜 emo 华语 · 30 首',
    '通勤路上的轻快英文歌',
    '健身撸铁的高燃电音',
    '2000 年代经典华语情歌',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- AI 选曲 ----------

  Future<void> _generate() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    FocusScope.of(context).unfocus();

    final config = await ref.read(llmConfigProvider.future);
    if (!config.isConfigured) {
      _goToSettings();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _playlist = null;
      _matchResults = null;
      _matchProgress = null;
    });

    try {
      final playlist = await ref
          .read(llmServiceProvider)
          .generatePlaylist(config, input);
      if (!mounted) return;
      setState(() => _playlist = playlist);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- 匹配 QQ 音乐 ----------

  Future<void> _match() async {
    final auth = ref.read(qqAuthProvider);
    if (!auth.isLoggedIn) {
      _goToLogin();
      return;
    }
    final playlist = _playlist;
    if (playlist == null) return;

    setState(() {
      _matching = true;
      _error = null;
      _matchResults = null;
      _matchProgress = List.filled(playlist.songs.length, null);
    });

    try {
      final results = await ref
          .read(matchServiceProvider)
          .matchPlaylist(
            playlist,
            auth: auth,
            onProgress: (i, r) {
              if (mounted) setState(() => _matchProgress?[i] = r);
            },
          );
      if (!mounted) return;
      setState(() {
        _matchResults = results;
        _matchProgress = null;
      });
      // 匹配完成：自动向下滚动，露出底部的「创建新歌单 / 加入已有歌单」
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _matchProgress = null;
      });
    } finally {
      if (mounted) setState(() => _matching = false);
    }
  }

  // ---------- 创建歌单 ----------

  // ---------- 创建 / 加入歌单 ----------

  /// 当前命中的歌曲
  List<QQSong> get _matchedSongs => (_matchResults ?? const [])
      .where((r) => r.isMatched)
      .map((r) => r.matched!)
      .toList();

  Future<void> _create() async {
    final auth = ref.read(qqAuthProvider);
    if (!auth.isLoggedIn) {
      _goToLogin();
      return;
    }
    final playlist = _playlist;
    if (playlist == null || _matchResults == null) return;

    final songs = _matchedSongs;
    if (songs.isEmpty) {
      AppToast.show(context, '没有可用的匹配结果');
      return;
    }

    setState(() => _creating = true);

    try {
      final client = ref.read(qqMusicClientProvider);
      final created = await client.createPlaylist(auth, playlist.title);
      await client.addSongsToPlaylist(auth, created.dirId, songs);
      if (!mounted) return;
      AppToast.show(context, '歌单「${playlist.title}」已创建', success: true);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '创建失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// 弹出「我创建的歌单」选择器，把命中歌曲加入其中
  Future<void> _showAddToExisting() async {
    final auth = ref.read(qqAuthProvider);
    if (!auth.isLoggedIn) {
      _goToLogin();
      return;
    }
    if (_matchedSongs.isEmpty) {
      AppToast.show(context, '没有可用的匹配结果');
      return;
    }

    final picked = await showModalBottomSheet<MyPlaylist>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (_) => _PlaylistPickerSheet(auth: auth),
    );
    if (picked == null || !mounted) return;
    await _addToPlaylist(picked);
  }

  Future<void> _addToPlaylist(MyPlaylist target) async {
    final auth = ref.read(qqAuthProvider);
    final songs = _matchedSongs;
    if (songs.isEmpty) return;

    setState(() => _creating = true);
    try {
      await ref
          .read(qqMusicClientProvider)
          .addSongsToPlaylist(auth, target.dirId, songs);
      if (!mounted) return;
      AppToast.show(context, '已加入歌单「${target.name}」', success: true);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '加入失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ---------- 播放 ----------

  Future<void> _playMatch(MatchResult r) async {
    final auth = ref.read(qqAuthProvider);
    final song = r.matched;
    if (song == null || _loadingPlayMid != null || _playAllLoading) return;
    unawaited(BatteryService.maybePromptOnPlay(context));
    setState(() => _loadingPlayMid = song.mid);
    try {
      final url = await ref
          .read(qqMusicClientProvider)
          .getPlayUrl(auth, song.mid);
      await ref
          .read(playerServiceProvider)
          .playUrl(url, title: song.name, cover: song.coverUrl);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loadingPlayMid = null);
    }
  }

  Future<void> _playAll() async {
    final auth = ref.read(qqAuthProvider);
    final results = _matchResults;
    if (results == null || _playAllLoading) return;
    unawaited(BatteryService.maybePromptOnPlay(context));
    final matched = results
        .where((r) => r.isMatched)
        .map((r) => r.matched!)
        .toList();
    if (matched.isEmpty) {
      if (!mounted) return;
      AppToast.show(context, '没有可播放的歌曲');
      return;
    }

    setState(() => _playAllLoading = true);
    try {
      // 3 路并行预取播放链接（顺序取几十首太慢，体感像卡住）
      final client = ref.read(qqMusicClientProvider);
      final urls = List<String?>.filled(matched.length, null);
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < matched.length) {
          final i = cursor++;
          try {
            urls[i] = await client.getPlayUrl(auth, matched[i].mid);
          } catch (_) {}
        }
      }

      await Future.wait([worker(), worker(), worker()]);

      final okUrls = <String>[];
      final titles = <String>[];
      final covers = <String>[];
      for (var i = 0; i < matched.length; i++) {
        final u = urls[i];
        if (u == null) continue;
        okUrls.add(u);
        titles.add(matched[i].name);
        covers.add(matched[i].coverUrl ?? '');
      }
      if (!mounted) return;
      if (okUrls.isEmpty) {
        AppToast.show(context, '没有可播放的歌曲');
        return;
      }
      await ref
          .read(playerServiceProvider)
          .playQueue(okUrls, titles: titles, covers: covers);
    } finally {
      if (mounted) setState(() => _playAllLoading = false);
    }
  }

  void _goToLogin() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LoginPage()));
  }

  void _goToSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(llmConfigProvider);
    final configured = configAsync.valueOrNull?.isConfigured ?? false;

    // 匹配状态：完成后歌单列表就地变为可播放曲库（不再单独弹出结果列表）
    final matchResults = _matchResults;
    final matchedDone = !_matching && matchResults != null;
    final List<MatchResult?>? rowStates = matchResults ?? _matchProgress;

    // 横屏（车机投屏 / 平板）：内容限宽居中，避免投屏窄窗口下控件被拉得过宽
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final pad = landscape ? 24.0 : 16.0;

    // 顶部固定 + 下方滚动
    return Column(
      children: [
        _Header(),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                children: [
                  if (!configured && !_loading)
                    _ConfigBanner(onTap: _goToSettings),

                  // ---------- 输入卡片 ----------
                  _PromptCard(
                    controller: _controller,
                    loading: _loading,
                    onGenerate: _generate,
                    examples: _examples,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBox(message: _error!),
                  ],

                  // ---------- AI 生成中 ----------
                  if (_loading) _LoadingCard(),

                  // ---------- 歌单（匹配在列表上就地完成） ----------
                  if (_playlist != null) ...[
                    const SizedBox(height: 16),
                    _PlaylistSection(
                      playlist: _playlist!,
                      onMatch: _matching ? null : _match,
                      matching: _matching,
                      matchedDone: matchedDone,
                      rowStates: rowStates,
                      loadingPlayMid: _loadingPlayMid,
                      playAllLoading: _playAllLoading,
                      onPlay: _playMatch,
                      onPlayAll: _playAll,
                    ),
                  ],

                  // ---------- 匹配完成后：入库操作 ----------
                  if (matchedDone) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _GradientButton(
                            label: _creating ? '创建中…' : '创建新歌单',
                            icon: Icons.add_chart_rounded,
                            loading: _creating,
                            onPressed: _creating ? null : _create,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SecondaryActionButton(
                            label: '加入已有歌单',
                            icon: Icons.playlist_add_rounded,
                            onPressed: _creating ? null : _showAddToExisting,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- 头部（固定，不随内容滚动；登录/设置入口已移至「我的」） ----------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    // 横屏（车机投屏 / 平板）：压缩头部高度，标题与副标题同一行
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, landscape ? 14 : 24),
      child: SafeArea(
        bottom: false,
        child: landscape
            ? Row(
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'QQ 音乐 AI 歌单',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '一句话，生成你的专属歌单',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'QQ 音乐 AI 歌单',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '一句话，生成你的专属歌单',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------- 输入卡片 ----------

class _PromptCard extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onGenerate;
  final List<String> examples;

  const _PromptCard({
    required this.controller,
    required this.loading,
    required this.onGenerate,
    required this.examples,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: AppColors.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onGenerate(),
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: const InputDecoration(
              hintText: '描述你想要的歌单，例如：深夜 emo 华语 · 30 首',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
            ),
          ),
          const SizedBox(height: 12),
          _GradientButton(
            label: loading ? 'AI 挑选歌曲中…' : '生成歌单',
            icon: Icons.auto_awesome_rounded,
            loading: loading,
            onPressed: loading ? null : onGenerate,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in examples)
                _ExampleChip(
                  label: e,
                  // 只填充输入框，由用户自己点「生成歌单」触发
                  onTap: () => controller.text = e,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ExampleChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandSoft,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 14, color: AppColors.brandDeep),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.brandDeep,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 渐变按钮 ----------

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: disabled ? null : AppColors.brandGradient,
        color: disabled ? const Color(0xFFB9C3BD) : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(icon, size: 19, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- 提示 / 错误 / 加载 ----------

class _ConfigBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _ConfigBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.key_rounded, color: Color(0xFFB28704), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '尚未配置 AI 服务',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF7A5D00),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '点击配置 API Key 后即可生成歌单',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF9C8A4D),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Color(0xFFB28704)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB0333E),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: AppColors.card(),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'AI 正在挑选歌曲…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

// ---------- 歌单卡片 ----------

class _PlaylistSection extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback? onMatch;
  final bool matching;
  final bool matchedDone; // 匹配完成：列表就地变为可播放的曲库列表
  final List<MatchResult?>? rowStates; // 每行匹配结果（null=该行还没轮到）
  final String? loadingPlayMid; // 正在获取播放链接的歌（行内转圈）
  final bool playAllLoading; // 播放全部预取中
  final void Function(MatchResult) onPlay;
  final VoidCallback onPlayAll;

  const _PlaylistSection({
    required this.playlist,
    required this.onMatch,
    required this.matching,
    required this.matchedDone,
    required this.rowStates,
    required this.loadingPlayMid,
    required this.playAllLoading,
    required this.onPlay,
    required this.onPlayAll,
  });

  int get _matchedCount =>
      rowStates?.where((r) => r?.isMatched ?? false).length ?? 0;

  MatchResult? _resultAt(int i) {
    final states = rowStates;
    if (states == null || i >= states.length) return null;
    return states[i];
  }

  /// 匹配中还没轮到的行：当前行 spinner，后续行空圈
  Widget? _pendingStatus(int index) {
    if (!matching) return null;
    final current = rowStates?.indexWhere((e) => e == null) ?? -1;
    if (index == current) {
      return const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      Icons.radio_button_unchecked_rounded,
      size: 15,
      color: AppColors.textSecondary.withValues(alpha: 0.5),
    );
  }

  Widget _playButton(MatchResult r) {
    return Material(
      color: AppColors.brandSoft,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onPlay(r),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            Icons.play_arrow_rounded,
            size: 20,
            color: AppColors.brandDeep,
          ),
        ),
      ),
    );
  }

  Widget _buildRow(int i) {
    final song = playlist.songs[i];
    final r = _resultAt(i);

    // 已命中：就地显示曲库真实条目，整行可点试听
    if (r != null && r.isMatched) {
      final loading = loadingPlayMid == r.matched!.mid;
      return _SongRow(
        index: i + 1,
        name: r.matched!.name,
        artist: r.matched!.artist,
        onTap: loading ? null : () => onPlay(r),
        trailing: loading
            // 取播放链接中：行内小转圈代替播放钮
            ? const Padding(
                padding: EdgeInsets.all(6.5),
                child: SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            : _playButton(r),
      );
    }
    // 未命中：保留 AI 原曲名，灰显
    if (r != null) {
      return _SongRow(
        index: i + 1,
        name: song.name,
        artist: '${song.artist} · 未在曲库中找到',
        dimmed: true,
        trailing: const Icon(
          Icons.cancel_rounded,
          size: 17,
          color: AppColors.danger,
        ),
      );
    }
    // 未开始 / 匹配中排队
    return _SongRow(
      index: i + 1,
      name: song.name,
      artist: song.artist,
      trailing: _pendingStatus(i),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (playlist.songs.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        matching
                            ? '正在匹配曲库…'
                            : matchedDone
                            ? '$_matchedCount/${playlist.songs.length} 命中 · 点击歌曲试听'
                            : '${playlist.songs.length} 首 · AI 精选',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (playlist.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                playlist.description,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          for (var i = 0; i < playlist.songs.length; i++) _buildRow(i),
          const SizedBox(height: 12),
          // 匹配完成后按钮就地切换为播放全部；之前是匹配按钮
          if (matchedDone)
            _GradientButton(
              label: playAllLoading ? '正在准备…' : '播放全部 ($_matchedCount 首)',
              icon: Icons.play_circle_fill_rounded,
              loading: playAllLoading,
              onPressed: !playAllLoading && _matchedCount > 0
                  ? onPlayAll
                  : null,
            )
          else
            _OutlineButton(
              label: matching ? '匹配中…' : '匹配 QQ 音乐曲库',
              icon: Icons.manage_search_rounded,
              loading: matching,
              onPressed: onMatch,
            ),
        ],
      ),
    );
  }
}

/// 歌单中的一行歌（命中后整行可点试听）
class _SongRow extends StatelessWidget {
  final int index;
  final String name;
  final String artist;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dimmed; // 未命中行灰显

  const _SongRow({
    required this.index,
    required this.name,
    required this.artist,
    this.trailing,
    this.onTap,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isAlt = index.isEven;
    final content = Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isAlt ? Colors.transparent : AppColors.bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$index',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.brand,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// 次级按钮（浅绿填充）
class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  const _OutlineButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Material(
      color: disabled ? AppColors.bg : AppColors.brandSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 18, color: AppColors.brandDeep),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.brandDeep,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 加入已有歌单：次级按钮 ----------

class _SecondaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _SecondaryActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Material(
      color: disabled ? AppColors.bg : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: disabled
                  ? Colors.transparent
                  : AppColors.brand.withValues(alpha: 0.5),
              width: 1.4,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: disabled ? AppColors.textSecondary : AppColors.brandDeep,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: disabled
                      ? AppColors.textSecondary
                      : AppColors.brandDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 加入已有歌单：选择弹窗 ----------

class _PlaylistPickerSheet extends ConsumerStatefulWidget {
  final QQAuthState auth;

  const _PlaylistPickerSheet({required this.auth});

  @override
  ConsumerState<_PlaylistPickerSheet> createState() =>
      _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<_PlaylistPickerSheet> {
  List<MyPlaylist>? _playlists;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await ref
          .read(qqMusicClientProvider)
          .getMyPlaylists(widget.auth);
      if (!mounted) return;
      // 只能往自己创建的歌单加歌；dirId 缺失的跳过
      setState(
        () => _playlists = all
            .where((p) => p.isCreated && p.dirId > 0 && p.id != '201')
            .toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9E2DD),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.brandDeep,
                  size: 21,
                ),
                SizedBox(width: 8),
                Text(
                  '加入到我创建的歌单',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '命中的歌曲将追加到所选歌单末尾',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Flexible(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_playlists == null && _error == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFB0333E),
                fontSize: 12.5,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('重试'),
              style: TextButton.styleFrom(foregroundColor: AppColors.brandDeep),
            ),
          ],
        ),
      );
    }
    final list = _playlists!;
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            '还没有自己创建的歌单\n先用「创建新歌单」建一个吧',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        return Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(context, p),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: AppColors.brandSoft,
                        child: p.coverUrl != null
                            ? Image.network(
                                p.coverUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.queue_music_rounded,
                                  size: 20,
                                  color: AppColors.brandDeep,
                                ),
                              )
                            : Icon(
                                Icons.queue_music_rounded,
                                size: 20,
                                color: AppColors.brandDeep,
                              ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${p.count} 首',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 21,
                      color: AppColors.brandDeep,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
