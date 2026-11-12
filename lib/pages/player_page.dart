import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../providers/providers.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

/// 全屏播放页：大封面（旋转）+ 可拖动进度 + 控制按钮 + 播放列表。
/// 竖屏为垂直布局，横屏自动切换为「封面左 / 控制右」布局。
/// 封面 / 按钮 / 字号按屏幕最短边等比缩放（[_scale]），
/// 车机投屏、平板等大屏不会显得控件过小；手机保持 1.0 不变。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotateCtrl;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _changesSub;

  bool _playing = false;
  String? _title;
  String? _cover;
  double _progress = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _index = 0;
  int _queueLen = 0;
  bool _scrubbing = false;
  double _scrubValue = 0;
  String? _modeHint;
  Timer? _modeHintTimer;
  Color _bgTop = const Color(0xFF1B4A38);
  Color _bgBottom = const Color(0xFF0C211A);
  String? _paletteFor;

  @override
  void initState() {
    super.initState();
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    final service = ref.read(playerServiceProvider);
    _playing = service.playing;
    _title = service.currentTitle;
    _cover = service.currentCover;
    _index = service.index;
    _queueLen = service.queueLength;
    if (_playing) _rotateCtrl.repeat();
    _syncPalette();

    _stateSub = service.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
        _title = service.currentTitle;
        _cover = service.currentCover;
        _index = service.index;
        _queueLen = service.queueLength;
      });
      if (_playing) {
        _rotateCtrl.repeat();
      } else {
        _rotateCtrl.stop();
      }
      _syncPalette();
    });
    _durSub = service.durationStream.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d ?? Duration.zero);
    });
    _posSub = service.positionStream.listen((p) {
      if (!mounted || _scrubbing) return;
      setState(() {
        _position = p;
        _progress = _duration.inMilliseconds > 0
            ? p.inMilliseconds / _duration.inMilliseconds
            : 0.0;
      });
    });
    // 队列恢复 / 外部变更时同步 UI
    _changesSub = service.changeStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = service.playing;
        _title = service.currentTitle;
        _cover = service.currentCover;
        _index = service.index;
        _queueLen = service.queueLength;
      });
      _syncPalette();
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _changesSub?.cancel();
    _modeHintTimer?.cancel();
    _rotateCtrl.dispose();
    super.dispose();
  }

  /// 背景跟随封面主色（参考 QQ 音乐），无封面/失败时保持当前背景
  Future<void> _syncPalette() async {
    final cover = _cover;
    if (cover == null || cover.isEmpty) {
      if (_paletteFor == null) return;
      _paletteFor = null;
      if (!mounted) return;
      setState(() {
        _bgTop = const Color(0xFF1B4A38);
        _bgBottom = const Color(0xFF0C211A);
      });
      return;
    }
    if (cover == _paletteFor) return;
    _paletteFor = cover;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(cover),
        maximumColorCount: 24,
      );
      var c =
          (palette.vibrantColor ?? palette.mutedColor ?? palette.dominantColor)
              ?.color;
      c ??= const Color(0xFF1B4A38);
      // 压暗到深色 UI 舒适区间
      final hsv = HSVColor.fromColor(c);
      final base = hsv
          .withValue(hsv.value.clamp(0.30, 0.55))
          .withSaturation(hsv.saturation.clamp(0.30, 0.80))
          .toColor();
      if (!mounted) return;
      setState(() {
        _bgTop = Color.lerp(base, Colors.black, 0.18)!;
        _bgBottom = Color.lerp(base, Colors.black, 0.80)!;
      });
    } catch (_) {
      // 取色失败：保持当前背景
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 尺寸缩放系数：车机投屏 / 平板等大屏（最短边 > 420dp）时封面、
  /// 按钮、字号等比放大；手机（最短边约 360–430dp）保持 1.0，观感不变。
  double _scale(Size size) => (size.shortestSide / 420).clamp(1.0, 2.2);

  @override
  Widget build(BuildContext context) {
    final service = ref.read(playerServiceProvider);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final scale = _scale(size);

    // 状态栏白色图标（顶部为品牌渐变）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusOverlayLight,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_bgTop, _bgBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: isLandscape
                ? _buildLandscape(service, size, scale)
                : _buildPortrait(service, scale),
          ),
        ),
      ),
    );
  }

  // ---------- 竖屏布局 ----------

  Widget _buildPortrait(PlayerService service, double scale) {
    return Column(
      children: [
        _buildTopBar(service, scale),
        Expanded(
          flex: 5,
          child: Center(
            child: _buildCover(
              MediaQuery.of(context).size.shortestSide - 80 * scale,
              scale,
            ),
          ),
        ),
        _buildTitleSection(scale: scale),
        SizedBox(height: 14 * scale),
        _buildProgress(service, scale),
        // 底部多留一档呼吸空间（SafeArea 已吃掉系统手势条）
        _buildControls(service, scale, bottomPad: 26 * scale),
      ],
    );
  }

  // ---------- 横屏布局 ----------

  Widget _buildLandscape(PlayerService service, Size size, double scale) {
    final coverSize = (size.height - 90 * scale).clamp(150.0, 300.0 * scale);
    return Row(
      children: [
        Expanded(flex: 5, child: Center(child: _buildCover(coverSize, scale))),
        Expanded(
          flex: 6,
          child: Padding(
            padding: EdgeInsets.only(right: 12 * scale),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTopBar(service, scale),
                _buildTitleSection(compact: true, scale: scale),
                SizedBox(height: 4 * scale),
                _buildProgress(service, scale),
                _buildControls(service, scale, bottomPad: 10 * scale),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 通用部件 ----------

  Widget _buildTopBar(PlayerService service, double scale) {
    return Padding(
      padding: EdgeInsets.fromLTRB(6 * scale, 4 * scale, 6 * scale, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 30 * scale,
            ),
          ),
          const Spacer(),
          Text(
            '正在播放 (${_index + 1}/$_queueLen)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12.5 * scale,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _showQueueSheet(service),
            icon: Icon(
              Icons.queue_music_rounded,
              color: Colors.white,
              size: 24 * scale,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(double size, double scale) {
    final s = size.clamp(150.0, 300.0 * scale);
    return RotationTransition(
      turns: _rotateCtrl,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 40 * scale,
              offset: Offset(0, 16 * scale),
            ),
          ],
        ),
        child: Stack(
          children: [
            ClipOval(
              child: Container(
                width: s,
                height: s,
                color: const Color(0xFF234E3E),
                child: _cover != null
                    ? Image.network(
                        _cover!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _VinylFallback(),
                      )
                    : _VinylFallback(),
              ),
            ),
            // 中心圆孔
            Center(
              child: Container(
                width: s * 0.2,
                height: s * 0.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0C211A),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 2 * scale,
                  ),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: Colors.white54,
                  size: 22 * scale,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleSection({bool compact = false, double scale = 1}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: (compact ? 8 : 32) * scale),
      child: Column(
        children: [
          Text(
            _title ?? '未在播放',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: (compact ? 16 : 19) * scale,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: (compact ? 3 : 6) * scale),
          Text(
            'QQ 音乐',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: (compact ? 11 : 12.5) * scale,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(PlayerService service, double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 26 * scale),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5 * scale,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7 * scale),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 14 * scale),
              activeTrackColor: AppColors.brand,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: AppColors.brand.withValues(alpha: 0.25),
            ),
            child: Slider(
              value: _scrubbing
                  ? _scrubValue.clamp(0.0, 1.0)
                  : _progress.clamp(0.0, 1.0),
              onChanged: _duration.inMilliseconds == 0
                  ? null
                  : (v) {
                      setState(() {
                        _scrubbing = true;
                        _scrubValue = v;
                      });
                    },
              onChangeEnd: (v) {
                final target = Duration(
                  milliseconds: (v * _duration.inMilliseconds).round(),
                );
                service.seek(target);
                setState(() {
                  _scrubbing = false;
                  _position = target;
                  _progress = v;
                });
              },
            ),
          ),
          SizedBox(height: 6 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmt(
                  _scrubbing
                      ? Duration(
                          milliseconds: (_scrubValue * _duration.inMilliseconds)
                              .round(),
                        )
                      : _position,
                ),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11 * scale,
                  height: 1.2,
                ),
              ),
              Text(
                _fmt(_duration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11 * scale,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
    PlayerService service,
    double scale, {
    double bottomPad = 10,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        26 * scale,
        6 * scale,
        26 * scale,
        bottomPad,
      ),
      child: SizedBox(
        height: 68 * scale,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 播放模式（提示悬浮在按钮上方，不影响整行对齐）
            SizedBox(
              width: 48 * scale,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      final nextMode =
                          PlayMode.values[(service.mode.index + 1) %
                              PlayMode.values.length];
                      service.setMode(nextMode);
                      _modeHintTimer?.cancel();
                      setState(() {
                        _modeHint = switch (nextMode) {
                          PlayMode.listLoop => '列表循环',
                          PlayMode.singleLoop => '单曲循环',
                          PlayMode.sequential => '顺序播放',
                          PlayMode.shuffle => '随机播放',
                        };
                      });
                      _modeHintTimer = Timer(
                        const Duration(milliseconds: 1300),
                        () {
                          if (mounted) setState(() => _modeHint = null);
                        },
                      );
                    },
                    icon: _modeIcon(
                      service.mode,
                      Colors.white.withValues(alpha: 0.75),
                      scale,
                    ),
                  ),
                  if (_modeHint != null)
                    Positioned(
                      top: -20 * scale,
                      left: -20 * scale,
                      right: -20 * scale,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _modeHint!,
                          key: ValueKey(_modeHint),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11 * scale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => service.previous(),
              icon: Icon(
                Icons.skip_previous_rounded,
                color: Colors.white,
                size: 38 * scale,
              ),
            ),
            // 播放 / 暂停（大按钮）
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () async {
                  await service.toggle();
                  if (mounted) setState(() {});
                },
                child: SizedBox(
                  width: 68 * scale,
                  height: 68 * scale,
                  child: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 42 * scale,
                    color: AppColors.brandDeep,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => service.next(),
              icon: Icon(
                Icons.skip_next_rounded,
                color: Colors.white,
                size: 38 * scale,
              ),
            ),
            // 播放列表
            IconButton(
              onPressed: () => _showQueueSheet(service),
              icon: Icon(
                Icons.format_list_bulleted_rounded,
                color: Colors.white.withValues(alpha: 0.75),
                size: 26 * scale,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeIcon(PlayMode mode, Color color, double scale) {
    switch (mode) {
      case PlayMode.listLoop:
        return Icon(Icons.repeat_rounded, color: color, size: 24 * scale);
      case PlayMode.singleLoop:
        return Icon(Icons.repeat_one_rounded, color: color, size: 24 * scale);
      case PlayMode.sequential:
        return Icon(Icons.low_priority_rounded, color: color, size: 24 * scale);
      case PlayMode.shuffle:
        return Icon(Icons.shuffle_rounded, color: color, size: 22 * scale);
    }
  }

  // ---------- 播放列表底部弹窗 ----------
  void _showQueueSheet(PlayerService service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14291F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final titles = service.titles;
            final covers = service.covers;
            final current = service.index;
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.65,
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          '播放列表',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${titles.length} 首',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        // 清空并停止
                        if (titles.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              await service.clear();
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(
                              Icons.delete_sweep_rounded,
                              size: 17,
                              color: Colors.white54,
                            ),
                            label: const Text(
                              '清空',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: titles.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  '播放列表为空',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: titles.length,
                              itemBuilder: (context, i) {
                                final isCurrent = i == current;
                                return ListTile(
                                  dense: true,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.white10,
                                      child:
                                          covers.isNotEmpty &&
                                              i < covers.length &&
                                              covers[i].isNotEmpty
                                          ? Image.network(
                                              covers[i],
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const Icon(
                                                    Icons.music_note_rounded,
                                                    size: 18,
                                                    color: Colors.white38,
                                                  ),
                                            )
                                          : const Icon(
                                              Icons.music_note_rounded,
                                              size: 18,
                                              color: Colors.white38,
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    titles[i].isEmpty ? '未知歌曲' : titles[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: isCurrent
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isCurrent
                                          ? AppColors.brand
                                          : Colors.white.withValues(
                                              alpha: 0.88,
                                            ),
                                    ),
                                  ),
                                  trailing: isCurrent
                                      ? Icon(
                                          Icons.graphic_eq_rounded,
                                          size: 18,
                                          color: AppColors.brand,
                                        )
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 17,
                                            color: Colors.white38,
                                          ),
                                          onPressed: () async {
                                            await service.removeFromQueue(i);
                                            if (service.queueLength == 0) {
                                              if (sheetCtx.mounted) {
                                                Navigator.pop(sheetCtx);
                                              }
                                            }
                                            setSheetState(() {});
                                            if (mounted) setState(() {});
                                          },
                                        ),
                                  onTap: () async {
                                    await service.playIndex(i);
                                    setSheetState(() {});
                                    if (mounted) setState(() {});
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 无封面时的黑胶 fallback
class _VinylFallback extends StatelessWidget {
  const _VinylFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.brandGradient),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white54, size: 64),
      ),
    );
  }
}
