import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/battery_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_update.dart';

/// 设置页：配置 LLM（base_url / api_key / model）
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  bool _saving = false;
  String _version = ''; // 当前应用版本（异步取）
  bool _checkingUpdate = false;
  bool _batteryIgnoring = true; // 省电策略是否已豁免（异步取，先按已允许渲染）

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadVersion();
    _loadBatteryState();
    // 从系统授权弹窗返回时刷新豁免状态
    WidgetsBinding.instance.addObserver(this);
    // 设置页保持打开时也要随主题重绘：路由 widget 是 const 规范化实例，
    // 全局树重建会被跳过，只有 State 自己 setState 才可靠
    AppColors.themeVersion.addListener(_onThemeChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadBatteryState();
  }

  Future<void> _loadBatteryState() async {
    final ok = await BatteryService.isIgnoring();
    if (!mounted) return;
    setState(() => _batteryIgnoring = ok);
  }

  Future<void> _requestBatteryIgnore() async {
    // 系统弹窗会覆盖应用；返回后由生命周期回调刷新状态
    await BatteryService.requestIgnore();
  }

  Future<void> _loadVersion() async {
    final v = await ref.read(updateServiceProvider).currentVersion();
    if (!mounted) return;
    setState(() => _version = v);
  }

  /// 手动检查更新：有新版本走完整更新流程
  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final update = await ref.read(updateServiceProvider).check();
      if (!mounted) return;
      if (update == null) {
        AppToast.show(context, '已是最新版本', success: true);
        return;
      }
      await runAppUpdateFlow(context, ref, update);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '检查更新失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadConfig() async {
    final config = await ref.read(settingsServiceProvider).load();
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    setState(() {});
  }

  Future<void> _save() async {
    final config = LlmConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
    );
    setState(() => _saving = true);
    await ref.read(settingsServiceProvider).save(config);
    ref.invalidate(llmConfigProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(context, '已保存', success: true);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    AppColors.themeVersion.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 状态栏黑色图标（浅色底）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusOverlayDark,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '设置',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
          backgroundColor: AppColors.bg,
          scrolledUnderElevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ---------- 投屏诊断（车机排查窗口方向/比例用） ----------
            // 非 const：主题切换时重建（const 实例会被复用，品牌色小图标不刷新）
            _DisplayDiagCard(),
            SizedBox(height: 12),

            // ---------- 主题色 ----------
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: AppColors.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.palette_rounded,
                        color: AppColors.brand,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '主题色',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '全局生效，重启后保持',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 14),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      for (final p in kThemePresets)
                        _ThemeSwatch(
                          preset: p,
                          selected: p.id == AppColors.preset.id,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),

            // ---------- 配置卡片 ----------
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              decoration: AppColors.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy_rounded,
                        color: AppColors.brand,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'AI 服务配置',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '兼容 OpenAI 协议的服务均可接入',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel(icon: Icons.link_rounded, text: '服务地址'),
                  TextField(
                    controller: _baseUrlController,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText: 'https://api.deepseek.com/v1',
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  _FieldLabel(icon: Icons.key_rounded, text: 'API Key'),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(hintText: 'sk-…'),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  _FieldLabel(icon: Icons.memory_rounded, text: '模型名称'),
                  TextField(
                    controller: _modelController,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText: 'deepseek-flash',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 保存按钮收进卡片内，与「应用更新」卡片结构一致
                  _SaveButton(saving: _saving, onSave: _save),
                  const SizedBox(height: 12),
                  // 支持服务与 Key 安全说明（AI 配置的附注）
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_rounded,
                          color: AppColors.brandDeep,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '支持 DeepSeek、Kimi、智谱 GLM、通义 Qwen、GPT-4o 等。'
                            'Key 仅保存在本机安全存储中，直连对应服务，不经任何中间服务器。',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ---------- 后台播放 ----------
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: AppColors.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        color: AppColors.brand,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '后台播放',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _batteryIgnoring ? '已允许后台运行' : '未开启',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _batteryIgnoring
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '熄屏连续播放需要加入电池优化豁免（省电策略「不限制」）',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (!_batteryIgnoring) ...[
                    const SizedBox(height: 12),
                    _BatteryButton(onTap: _requestBatteryIgnore),
                  ],
                ],
              ),
            ),
            // ---------- 应用更新 ----------
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: AppColors.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.system_update_alt_rounded,
                        color: AppColors.brand,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '应用更新',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _version.isEmpty ? '当前版本 …' : '当前版本 v$_version',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CheckUpdateButton(
                    checking: _checkingUpdate,
                    onTap: _checkUpdate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主题色圆形选择器
class _ThemeSwatch extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;

  const _ThemeSwatch({required this.preset, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 本地透明 Material 承载 Ink：装饰与涟漪都画在它自己身上。
        // 直接挂页面级 Material 时，Ink 在 ListView 里会拿到过期变换、画错位置
        Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: selected ? null : () => AppColors.applyPreset(preset),
            child: Ink(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [preset.brand, preset.brandDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                // 选中态：品牌色柔光（不用黑圈，和彩色圆不搭）
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: preset.brand.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 24,
                    )
                  : null,
            ),
          ),
        ),
        SizedBox(height: 5),
        Text(
          preset.name,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FieldLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.brand),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;

  const _SaveButton({required this.saving, required this.onSave});

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
          onTap: saving ? null : onSave,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.save_rounded, size: 19, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  saving ? '保存中…' : '保存配置',
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

/// 后台播放设置按钮（品牌渐变胶囊，同检查更新按钮风格）
class _BatteryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BatteryButton({required this.onTap});

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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bolt_rounded, size: 19, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  '设置为不限制',
                  style: const TextStyle(
                    color: Colors.white,
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

/// 检查更新按钮（品牌渐变胶囊，同保存按钮风格）
class _CheckUpdateButton extends StatelessWidget {
  final bool checking;
  final VoidCallback onTap;

  const _CheckUpdateButton({required this.checking, required this.onTap});

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
          onTap: checking ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (checking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.manage_search_rounded,
                    size: 19,
                    color: Colors.white,
                  ),
                const SizedBox(width: 8),
                Text(
                  checking ? '检查中…' : '检查更新',
                  style: const TextStyle(
                    color: Colors.white,
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

/// 投屏诊断卡片：展示当前窗口 / 显示器的关键参数（原生 + Flutter 两侧），
/// 用于车机实车排查投屏窗口的方向与 dp 比例问题。
///
/// 关注点：
/// - `displayId`：投屏虚拟屏通常不是 0（手机主屏为 0）；
/// - `rotation` 与 `configOrientation`：窗口 surface 方向是否被系统改写；
/// - `configWidthDp/HeightDp` 与 Flutter `size`：互联框架是否拉伸了 dp 比例；
/// - `densityDpi`：车机低密度下控件物理尺寸的依据。
class _DisplayDiagCard extends StatefulWidget {
  const _DisplayDiagCard();

  @override
  State<_DisplayDiagCard> createState() => _DisplayDiagCardState();
}

class _DisplayDiagCardState extends State<_DisplayDiagCard> {
  static const _channel = MethodChannel('qq_music_ai/display');
  Map<String, dynamic>? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'displayInfo',
      );
      if (!mounted) return;
      setState(() {
        _info = raw?.cast<String, dynamic>();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _copy(BuildContext context) async {
    final mq = MediaQuery.of(context);
    final lines = <String>[
      '--- 投屏诊断 ${DateTime.now()} ---',
      'flutter.size=${mq.size.width}x${mq.size.height}',
      'flutter.orientation=${mq.orientation.name}',
      'flutter.dpr=${mq.devicePixelRatio}',
      'flutter.textScale=${mq.textScaler.scale(14)}',
      if (_info != null)
        for (final e in _info!.entries) 'native.${e.key}=${e.value}',
      if (_error != null) 'error=$_error',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (context.mounted) AppToast.show(context, '诊断信息已复制', success: true);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final info = _info;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: AppColors.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cast_rounded, color: AppColors.brand, size: 20),
              const SizedBox(width: 8),
              const Text(
                '投屏诊断',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '车机投屏异常时把以下参数发给开发者（点复制）',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Text(
              '读取失败：$_error',
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
            )
          else if (info == null)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            _diagRow(
              'Flutter 窗口',
              '${mq.size.width.toStringAsFixed(0)}×${mq.size.height.toStringAsFixed(0)} dp · ${mq.orientation.name} · dpr ${mq.devicePixelRatio.toStringAsFixed(2)}',
            ),
            _diagRow(
              '显示器',
              'id=${info['displayId']} rotation=${info['rotation']} '
                  '${info['widthPx']}×${info['heightPx']}px @${info['densityDpi']}dpi',
            ),
            _diagRow(
              '系统配置',
              'orientation=${info['configOrientation']} '
                  '${info['configWidthDp']}×${info['configHeightDp']}dp '
                  '@${info['configDensityDpi']}dpi',
            ),
          ],
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
