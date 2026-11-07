import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/qq_music_client.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'login_page.dart';
import 'playlist_detail_page.dart';
import 'settings_page.dart';

/// 我的：登录状态 + 我的歌单（可查看、可播放）
class MinePage extends ConsumerStatefulWidget {
  const MinePage({super.key});

  @override
  ConsumerState<MinePage> createState() => MinePageState();
}

class MinePageState extends ConsumerState<MinePage> {
  List<MyPlaylist>? _playlists;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 进入页面时若已登录则自动加载
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfLoggedIn());
  }

  void _loadIfLoggedIn() {
    final auth = ref.read(qqAuthProvider);
    if (auth.isLoggedIn && _playlists == null && !_loading) {
      _load();
    }
  }

  /// 供外部（Tab 切换）触发强制刷新
  void refresh() {
    if (ref.read(qqAuthProvider).isLoggedIn) _load();
  }

  Future<void> _load() async {
    final auth = ref.read(qqAuthProvider);
    if (!auth.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await ref.read(qqMusicClientProvider).getMyPlaylists(auth);
      if (!mounted) return;
      setState(() => _playlists = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('退出登录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: const Text('退出后需要重新扫码登录，确定吗？',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 同步清理 WebView Cookie，否则重新登录会自动抓回旧账号
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    await ref.read(qqAuthProvider.notifier).logout();
    if (!mounted) return;
    setState(() {
      _playlists = null;
      _error = null;
    });
    AppToast.show(context, '已退出登录');
  }

  void _goToLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    // 登录页返回后刷新
    _loadIfLoggedIn();
    setState(() {});
  }

  // ---------- 分组标题 ----------

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 13,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count 个',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 歌单操作（改名 / 删除） ----------

  void _showPlaylistActions(MyPlaylist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD9E2DD),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: AppColors.brandDeep, size: 21),
              title: const Text('修改名称',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _renamePlaylist(playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger, size: 21),
              title: const Text('删除歌单',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _deletePlaylist(playlist);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _renamePlaylist(MyPlaylist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('修改歌单名称',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: '输入新名称',
            filled: true,
            fillColor: AppColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(dialogCtx, v);
            },
            child: const Text('保存',
                style: TextStyle(
                    color: AppColors.brandDeep,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName == playlist.name || !mounted) return;

    // 改名 = 读歌 → 新名重建 → 迁移 → 删旧（官方无独立改名接口）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
        content: SizedBox(
          width: 60,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('正在迁移歌曲…', style: TextStyle(fontSize: 14))),
            ],
          ),
        ),
      ),
    );

    try {
      await ref.read(qqMusicClientProvider).renamePlaylist(
            ref.read(qqAuthProvider),
            playlist: playlist,
            newName: newName,
          );
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭进度框
      AppToast.show(context, '已重命名为「$newName」', success: true);
      _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.show(context, '重命名失败：$e', error: true);
    }
  }

  Future<void> _deletePlaylist(MyPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除歌单',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Text('确定删除「${playlist.name}」吗？\n该操作不可恢复。',
            style: const TextStyle(
                fontSize: 13.5, height: 1.5, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('删除',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(qqMusicClientProvider).deletePlaylist(
            ref.read(qqAuthProvider),
            dirId: playlist.dirId,
          );
      if (!mounted) return;
      AppToast.show(context, '歌单「${playlist.name}」已删除', success: true);
      _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '删除失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(qqAuthProvider);
    final created =
        (_playlists ?? const <MyPlaylist>[]).where((p) => p.isCreated).toList();
    final collected =
        (_playlists ?? const <MyPlaylist>[]).where((p) => !p.isCreated).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // ---------- 头部 ----------
            Container(
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        Icon(Icons.person_rounded,
                            color: Colors.white, size: 26),
                        SizedBox(width: 10),
                        Text(
                          '我的',
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
                      auth.isLoggedIn ? 'QQ：${auth.uin}' : '登录后可查看与播放自己的歌单',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---------- 未登录 ----------
            if (!auth.isLoggedIn) ...[
              const SizedBox(height: 24),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(28),
                decoration: AppColors.card(),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.music_note_rounded,
                          color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '还没有登录 QQ 音乐',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '登录后可以在这里查看自己的歌单并播放',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    _LoginButton(onTap: _goToLogin),
                  ],
                ),
              ),
            ],

            // ---------- 已登录：歌单列表（自建 / 收藏 分组） ----------
            if (auth.isLoggedIn) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(
                  children: [
                    const Text(
                      '我的歌单',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_playlists != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_playlists!.length} 个',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (_loading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        color: Color(0xFFB0333E), fontSize: 12.5, height: 1.5),
                  ),
                ),
              if (_playlists != null && _playlists!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('还没有歌单，去首页创建一个吧',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                ),
              if (_playlists != null) ...[
                // ---------- 自建歌单 ----------
                _sectionHeader('自建歌单', created.length),
                for (var i = 0; i < created.length; i++)
                  _PlaylistTile(
                    playlist: created[i],
                    first: i == 0,
                    onMore: created[i].dirId > 0 && created[i].id != '201'
                        ? () => _showPlaylistActions(created[i])
                        : null,
                  ),
                // ---------- 收藏歌单 ----------
                if (collected.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _sectionHeader('收藏歌单', collected.length),
                  for (var i = 0; i < collected.length; i++)
                    _PlaylistTile(
                      playlist: collected[i],
                      first: i == 0,
                    ),
                ],
              ],
            ],
            // ---------- 菜单（设置 / 退出登录） ----------
            Container(
              margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              decoration: AppColors.card(),
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.settings_rounded,
                    label: '设置',
                    subtitle: 'AI 服务配置（API Key / 模型）',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsPage()),
                      );
                    },
                  ),
                  if (auth.isLoggedIn) ...[
                    const Divider(indent: 58),
                    _MenuRow(
                      icon: Icons.logout_rounded,
                      label: '退出登录',
                      danger: true,
                      onTap: _logout,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ---------- 菜单行 ----------

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.brandDeep;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: danger
                      ? AppColors.dangerSoft
                      : AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: danger
                            ? AppColors.danger
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 歌单条目 ----------

class _PlaylistTile extends StatelessWidget {
  final MyPlaylist playlist;
  final bool first;
  final VoidCallback? onMore;

  const _PlaylistTile({
    required this.playlist,
    required this.first,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, first ? 8 : 8, 16, 0),
      decoration: AppColors.card(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PlaylistDetailPage(playlist: playlist),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: AppColors.brandSoft,
                    child: playlist.coverUrl != null
                        ? Image.network(
                            playlist.coverUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.queue_music_rounded,
                                color: AppColors.brandDeep),
                          )
                        : const Icon(Icons.queue_music_rounded,
                            color: AppColors.brandDeep),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${playlist.count} 首',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                onMore != null
                    ? IconButton(
                        onPressed: onMore,
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 20, color: AppColors.textSecondary),
                      )
                    : const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- 登录按钮 ----------

class _LoginButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LoginButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
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
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.login_rounded, color: Colors.white, size: 19),
                SizedBox(width: 8),
                Text(
                  '去登录',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
