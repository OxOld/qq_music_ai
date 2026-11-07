import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// 设置页：配置 LLM（base_url / api_key / model）
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        backgroundColor: AppColors.bg,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
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
                  decoration: const InputDecoration(hintText: 'deepseek-flash'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---------- 隐私说明 ----------
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brandSoft.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_rounded,
                  color: AppColors.brandDeep,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '支持 DeepSeek、Kimi、智谱 GLM、通义 Qwen、GPT-4o 等。'
                    'Key 仅保存在本机安全存储中，直连对应服务，不经任何中间服务器。',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SaveButton(saving: _saving, onSave: _save),
        ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        if (selected) return;
        await AppColors.applyPreset(preset);
      },
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [preset.brand, preset.brandDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.textPrimary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 24)
                : null,
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
      ),
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
