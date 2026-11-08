import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../models/qq_song.dart';
import '../providers/providers.dart';
import '../services/match_service.dart';
import '../services/qq_music_client.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

/// AI 补充歌单弹层：先出建议列表（纯 AI 推荐，勾选筛选），
/// 满意后「匹配并添加」（逐首匹配曲库，命中的自动加入歌单）；不满意可「换一批」。
Future<void> showSongManageSheet(
  BuildContext context, {
  required MyPlaylist playlist,
  required List<QQSong> currentSongs,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) => _SongManageSheet(
      playlist: playlist,
      currentSongs: currentSongs,
      onChanged: onChanged,
    ),
  );
}

class _SongManageSheet extends ConsumerStatefulWidget {
  final MyPlaylist playlist;
  final List<QQSong> currentSongs;
  final VoidCallback onChanged;

  const _SongManageSheet({
    required this.playlist,
    required this.currentSongs,
    required this.onChanged,
  });

  @override
  ConsumerState<_SongManageSheet> createState() => _SongManageSheetState();
}

class _SongManageSheetState extends ConsumerState<_SongManageSheet> {
  List<Song> _suggestions = const [];
  List<MatchResult?>? _matchProgress; // 匹配中：逐首进度（null=还没轮到）
  final Set<int> _selected = {}; // 勾选的建议下标
  bool _loadingLlm = false;
  bool _matching = false; // 匹配并添加进行中
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  // ---------- 数据 ----------

  Future<void> _loadSuggestions() async {
    if (_loadingLlm) return;
    setState(() {
      _loadingLlm = true;
      _error = null;
    });
    try {
      final config = await ref.read(llmConfigProvider.future);
      if (!config.isConfigured) {
        if (!mounted) return;
        setState(() {
          _loadingLlm = false;
          _error = '尚未配置 AI 服务，请先到设置页填写 API Key';
        });
        return;
      }
      final suggestions = await ref
          .read(llmServiceProvider)
          .suggestSongsForPlaylist(
            config,
            playlistName: widget.playlist.name,
            existing: widget.currentSongs
                .map((s) => Song(name: s.name, artist: s.artist))
                .toList(),
            exclude: _suggestions.map((s) => s.name).toList(),
          );
      if (!mounted) return;
      setState(() {
        _loadingLlm = false;
        _suggestions = suggestions;
        _selected.clear();
        for (var i = 0; i < suggestions.length; i++) {
          _selected.add(i);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLlm = false;
        _error = e.toString();
      });
    }
  }

  /// 匹配并添加：逐首匹配曲库，命中的自动加入歌单
  Future<void> _matchAndAdd() async {
    if (_matching) return;
    final selected = [
      for (final i in _selected)
        if (i < _suggestions.length) _suggestions[i],
    ];
    if (selected.isEmpty) return;

    final auth = ref.read(qqAuthProvider);
    final client = ref.read(qqMusicClientProvider);

    setState(() {
      _matching = true;
      _error = null;
      _matchProgress = List.filled(selected.length, null);
    });

    try {
      final results = await ref
          .read(matchServiceProvider)
          .matchSongs(
            selected,
            auth: auth,
            onProgress: (i, r) {
              if (mounted) setState(() => _matchProgress?[i] = r);
            },
          );
      final matched = [
        for (final r in results)
          if (r.isMatched) r.matched!,
      ];
      if (matched.isEmpty) {
        if (!mounted) return;
        setState(() {
          _matching = false;
          _matchProgress = null;
          _error = '勾选的歌曲都没有在曲库中找到，换一批试试';
        });
        return;
      }
      await client.addSongsToPlaylist(auth, widget.playlist.dirId, matched);
      if (!mounted) return;
      final missed = results.length - matched.length;
      AppToast.show(
        context,
        missed > 0
            ? '已添加 ${matched.length} 首（$missed 首未在曲库找到）'
            : '已添加 ${matched.length} 首到「${widget.playlist.name}」',
        success: true,
      );
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _matching = false;
        _matchProgress = null;
        _error = e.toString();
      });
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
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
            Text(
              'AI 补充「${widget.playlist.name}」',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _matching ? '正在匹配曲库并添加…' : '按歌单风格推荐，勾选想要的，不满意可换一批',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(child: _buildBody()),
            const SizedBox(height: 10),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingLlm) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                'AI 正在挑选适合补充的歌曲…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Color(0xFFB0333E),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadSuggestions,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandDeep,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_matching) {
      // 匹配进度：逐首显示
      final progress = _matchProgress ?? const <MatchResult?>[];
      return ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: progress.length,
        itemBuilder: (context, i) => _matchProgressRow(i, progress[i]),
      );
    }
    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _suggestions.length,
      itemBuilder: (context, i) {
        final s = _suggestions[i];
        final selected = _selected.contains(i);
        return _checkRow(
          title: s.name,
          subtitle: s.artist,
          checked: selected,
          onChanged: (v) {
            setState(() {
              if (v ?? false) {
                _selected.add(i);
              } else {
                _selected.remove(i);
              }
            });
          },
          onTap: () {
            setState(() {
              if (selected) {
                _selected.remove(i);
              } else {
                _selected.add(i);
              }
            });
          },
        );
      },
    );
  }

  Widget _matchProgressRow(int i, MatchResult? r) {
    Widget trailing;
    if (r != null) {
      trailing = Icon(
        r.isMatched ? Icons.check_circle_rounded : Icons.cancel_rounded,
        size: 17,
        color: r.isMatched ? AppColors.success : AppColors.danger,
      );
    } else {
      final current = (_matchProgress ?? const <MatchResult?>[]).indexWhere(
        (e) => e == null,
      );
      trailing = i == current
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.radio_button_unchecked_rounded,
              size: 15,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            );
    }
    final original = i < _suggestions.length
        ? _suggestions[i]
        : const Song(name: '', artist: '');
    return _staticRow(
      title: r?.matched?.name ?? original.name,
      subtitle: r?.matched?.artist ?? original.artist,
      dimmed: r != null && !r.isMatched,
      trailing: trailing,
    );
  }

  // ---------- 通用行 / 底部按钮 ----------

  Widget _checkRow({
    required String title,
    required String subtitle,
    required bool checked,
    required ValueChanged<bool?>? onChanged,
    required VoidCallback? onTap,
  }) {
    final row = Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: IgnorePointer(
              child: Checkbox(
                value: checked,
                onChanged: onChanged,
                activeColor: AppColors.brand,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(
                  color: AppColors.textSecondary.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: row,
      ),
    );
  }

  Widget _staticRow({
    required String title,
    required String subtitle,
    required bool dimmed,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Opacity(
        opacity: dimmed ? 0.5 : 1,
        child: Row(
          children: [
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final count = _selected.length;
    final canAdd = !_loadingLlm && !_matching && count > 0;
    return Row(
      children: [
        // 换一批：对当前这批不满意时重新让 AI 推荐（提示词排除已出过的）
        Expanded(
          child: _FooterButton(
            label: '换一批',
            icon: Icons.refresh_rounded,
            soft: true,
            loading: _loadingLlm,
            onPressed: _matching || _loadingLlm || _suggestions.isEmpty
                ? null
                : _loadSuggestions,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _FooterButton(
            label: _matching ? '匹配中…' : '匹配并添加 ($count)',
            icon: Icons.check_circle_outline_rounded,
            loading: _matching,
            onPressed: canAdd ? _matchAndAdd : null,
          ),
        ),
      ],
    );
  }
}

/// 弹层底部按钮：soft=浅底换一批；默认品牌渐变主操作
class _FooterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool soft;
  final bool loading;
  final VoidCallback? onPressed;

  const _FooterButton({
    required this.label,
    required this.icon,
    this.soft = false,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    if (soft) {
      return Material(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
                  Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: disabled ? null : AppColors.brandGradient,
        color: disabled ? AppColors.bg : null,
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
            padding: const EdgeInsets.symmetric(vertical: 12),
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
                  Icon(
                    icon,
                    size: 19,
                    color: disabled ? AppColors.textSecondary : Colors.white,
                  ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: disabled ? AppColors.textSecondary : Colors.white,
                    fontSize: 15,
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
