import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/llm_service.dart';
import '../services/prompt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/gradient_button.dart';

/// AI 提示词设置页
///
/// 只编辑两套提示词的「前缀」（角色、风格、额外要求）。JSON 结构、字段
/// 规范等固定规则由 [LlmService] 维护，请求时自动拼在前缀之后；页面里
/// 可只读查看固定规则。清空输入框 = 恢复默认文案。
class PromptSettingsPage extends ConsumerStatefulWidget {
  const PromptSettingsPage({super.key});

  @override
  ConsumerState<PromptSettingsPage> createState() => _PromptSettingsPageState();
}

class _PromptSettingsPageState extends ConsumerState<PromptSettingsPage> {
  final _generateCtrl = TextEditingController();
  final _suggestCtrl = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ref.read(promptServiceProvider).load();
    _generateCtrl.text = config.resolvedGeneratePrefix;
    _suggestCtrl.text = config.resolvedSuggestPrefix;
    if (mounted) setState(() => _loaded = true);
  }

  /// 与内置默认一致（或为空）时存空串：跟随后续版本更新默认文案
  String _normalize(String text, String defaultText) {
    final value = text.trim();
    if (value.isEmpty || value == defaultText.trim()) return '';
    return value;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(promptServiceProvider)
          .save(
            PromptConfig(
              generatePrefix: _normalize(
                _generateCtrl.text,
                PromptService.defaultGeneratePrefix,
              ),
              suggestPrefix: _normalize(
                _suggestCtrl.text,
                PromptService.defaultSuggestPrefix,
              ),
            ),
          );
      ref.invalidate(promptConfigProvider);
      if (!mounted) return;
      AppToast.show(context, '提示词已保存', success: true);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '保存失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _generateCtrl.dispose();
    _suggestCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusOverlayDark,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'AI 提示词',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
          backgroundColor: AppColors.bg,
          scrolledUnderElevation: 0,
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      const _IntroNote(),
                      const SizedBox(height: 16),
                      _PromptEditorCard(
                        icon: Icons.auto_awesome_rounded,
                        title: '歌单生成',
                        caption: '决定 AI 如何根据场景描述选曲',
                        controller: _generateCtrl,
                        defaultText: PromptService.defaultGeneratePrefix,
                        fixedRules: LlmService.generateFixedTail,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _PromptEditorCard(
                        icon: Icons.playlist_add_rounded,
                        title: '补歌推荐',
                        caption: '决定 AI 如何为已有歌单挑选未收录的新歌',
                        controller: _suggestCtrl,
                        defaultText: PromptService.defaultSuggestPrefix,
                        fixedRules: LlmService.suggestFixedTail,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 20),
                      GradientButton(
                        label: '保存提示词',
                        loadingLabel: '保存中…',
                        icon: Icons.save_rounded,
                        loading: _saving,
                        onTap: _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// 顶部说明
class _IntroNote extends StatelessWidget {
  const _IntroNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.tips_and_updates_rounded,
            color: AppColors.brandDeep,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '只需要写角色设定、风格偏好和额外要求。JSON 结构与字段规范由 App '
              '自动拼接在末尾（点卡片右上角的 </> 查看），改前缀不会破坏解析；'
              '清空输入框或点「恢复默认」即使用内置文案。保存后对下一次生成生效。',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个提示词编辑卡片
class _PromptEditorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;
  final TextEditingController controller;
  final String defaultText;
  final String fixedRules;
  final VoidCallback onChanged;

  const _PromptEditorCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.controller,
    required this.defaultText,
    required this.fixedRules,
    required this.onChanged,
  });

  bool get _isCustom {
    final text = controller.text.trim();
    return text.isNotEmpty && text != defaultText.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: AppColors.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.brand, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(custom: _isCustom),
              const Spacer(),
              IconButton(
                tooltip: '查看固定规则',
                visualDensity: VisualDensity.compact,
                onPressed: () => _showFixedRules(context),
                icon: Icon(
                  Icons.code_rounded,
                  size: 19,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            inputFormatters: [LengthLimitingTextInputFormatter(2000)],
            onChanged: (_) => onChanged(),
            style: const TextStyle(fontSize: 13.5, height: 1.5),
            decoration: InputDecoration(
              hintText: '留空使用默认提示词',
              filled: true,
              fillColor: AppColors.bg.withValues(alpha: 0.7),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '清空 = 使用默认提示词',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  controller.text = defaultText;
                  onChanged();
                },
                child: const Text('恢复默认', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 只读预览自动拼接的固定规则段
  void _showFixedRules(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetCtx).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title · 固定规则',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '以下内容由 App 自动追加在可编辑前缀之后，不可编辑；升级 App 时随版本更新。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          fixedRules.trim(),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.55,
                            fontFamily: 'monospace',
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: fixedRules.trim()),
                        );
                        if (sheetCtx.mounted) {
                          AppToast.show(sheetCtx, '固定规则已复制', success: true);
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('复制', style: TextStyle(fontSize: 12.5)),
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

/// 「默认 / 已自定义」状态徽标
class _StatusChip extends StatelessWidget {
  final bool custom;

  const _StatusChip({required this.custom});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: custom ? AppColors.brandSoft : const Color(0xFFEEF1EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        custom ? '已自定义' : '默认',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: custom ? AppColors.brandDeep : AppColors.textSecondary,
        ),
      ),
    );
  }
}
