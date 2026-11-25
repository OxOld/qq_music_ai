import 'package:shared_preferences/shared_preferences.dart';

/// AI 提示词配置
///
/// 只保存用户可编辑的「前缀」（角色设定、风格偏好、额外要求）。JSON 结构、
/// 字段规范等固定规则由 [LlmService] 维护，调用时自动拼接在前缀之后——
/// 用户怎么改前缀都不会破坏 JSON 解析。
class PromptConfig {
  /// 歌单生成的可编辑前缀（空串 = 使用内置默认）
  final String generatePrefix;

  /// 补歌推荐的可编辑前缀（空串 = 使用内置默认）
  final String suggestPrefix;

  const PromptConfig({this.generatePrefix = '', this.suggestPrefix = ''});

  /// 歌单生成是否使用自定义前缀
  bool get generateIsCustom => generatePrefix.trim().isNotEmpty;

  /// 补歌推荐是否使用自定义前缀
  bool get suggestIsCustom => suggestPrefix.trim().isNotEmpty;

  /// 实际发给模型的歌单生成前缀（空值回退默认）
  String get resolvedGeneratePrefix => generateIsCustom
      ? generatePrefix.trim()
      : PromptService.defaultGeneratePrefix;

  /// 实际发给模型的补歌推荐前缀（空值回退默认）
  String get resolvedSuggestPrefix => suggestIsCustom
      ? suggestPrefix.trim()
      : PromptService.defaultSuggestPrefix;
}

/// AI 提示词持久化服务
///
/// 提示词不是密钥，用 shared_preferences 保存即可；与 LLM 的 base_url /
/// api_key（secure_storage）分开，互不影响。
class PromptService {
  static const _kGeneratePrefix = 'prompt_generate_prefix';
  static const _kSuggestPrefix = 'prompt_suggest_prefix';

  /// 「歌单生成」默认前缀（与旧版硬编码提示词的第一段一致）
  static const defaultGeneratePrefix =
      '你是一位专业的音乐策展人。请根据用户描述的场景、情绪、曲风、语言、年代等需求，生成一份精选歌单。';

  /// 「补歌推荐」默认前缀（与旧版硬编码提示词的第一段一致）
  static const defaultSuggestPrefix =
      '你是一位专业的音乐策展人。用户会给出一份已有歌单的名称与全部歌曲，'
      '请为这份歌单推荐一批"还没有收录"的新歌：延续歌单的整体风格、情绪与年代，'
      '与已有歌曲互补而不重复。';

  /// 读取提示词配置；读取失败按全默认处理
  Future<PromptConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PromptConfig(
        generatePrefix: prefs.getString(_kGeneratePrefix) ?? '',
        suggestPrefix: prefs.getString(_kSuggestPrefix) ?? '',
      );
    } catch (_) {
      return const PromptConfig();
    }
  }

  /// 保存提示词配置（空串表示使用默认）
  Future<void> save(PromptConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGeneratePrefix, config.generatePrefix.trim());
    await prefs.setString(_kSuggestPrefix, config.suggestPrefix.trim());
  }
}
