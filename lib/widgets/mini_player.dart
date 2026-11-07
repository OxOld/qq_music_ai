import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/player_page.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// 迷你播放条：显示当前歌曲、播放/暂停、上一首/下一首。
/// 点击中部区域进入全屏播放页；无播放内容时自动隐藏。
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _changesSub;
  bool _playing = false;
  String? _title;
  String? _cover;
  double _progress = 0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    final service = ref.read(playerServiceProvider);
    _playing = service.playing;
    _title = service.currentTitle;
    _cover = service.currentCover;

    _stateSub = service.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
        _title = service.currentTitle;
        _cover = service.currentCover;
      });
    });
    _durSub = service.durationStream.listen((d) {
      _duration = d ?? Duration.zero;
      _updateProgress();
    });
    _posSub = service.positionStream.listen((p) {
      _position = p;
      _updateProgress();
    });
    // 队列恢复 / 外部变更时同步 UI
    _changesSub = service.changeStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = service.playing;
        _title = service.currentTitle;
        _cover = service.currentCover;
      });
    });
  }

  void _updateProgress() {
    if (!mounted) return;
    setState(() {
      _progress = _duration.inMilliseconds > 0
          ? _position.inMilliseconds / _duration.inMilliseconds
          : 0.0;
    });
  }

  void _openPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerPage()),
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _changesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(playerServiceProvider);
    if (!service.hasQueue) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A1C2420),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          LinearProgressIndicator(
            value: _progress.clamp(0.0, 1.0),
            minHeight: 2.5,
            backgroundColor: Colors.transparent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Row(
              children: [
                // 封面（点击进入播放页）
                GestureDetector(
                  onTap: _openPlayer,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 38,
                      height: 38,
                      color: AppColors.brandSoft,
                      child: _cover != null && _cover!.isNotEmpty
                          ? Image.network(
                              _cover!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                  Icons.music_note_rounded,
                                  color: AppColors.brandDeep,
                                  size: 19),
                            )
                          : const Icon(Icons.music_note_rounded,
                              color: AppColors.brandDeep, size: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                // 歌名（点击进入播放页）
                Expanded(
                  child: GestureDetector(
                    onTap: _openPlayer,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title ?? '正在播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          _playing ? '正在播放 · 点击查看' : '已暂停 · 点击查看',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => service.previous(),
                  icon: const Icon(Icons.skip_previous_rounded,
                      size: 26, color: AppColors.textPrimary),
                ),
                Material(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () async {
                      await service.toggle();
                      if (mounted) setState(() => _playing = service.playing);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 26,
                        color: AppColors.brandDeep,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => service.next(),
                  icon: const Icon(Icons.skip_next_rounded,
                      size: 26, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
