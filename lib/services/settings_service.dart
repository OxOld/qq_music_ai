import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// LLM 配置
class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  bool get isConfigured => apiKey.trim().isNotEmpty;

  LlmConfig copyWith({String? baseUrl, String? apiKey, String? model}) {
    return LlmConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }
}

/// 设置持久化服务（Keychain / Keystore）
class SettingsService {
  static const _storage = FlutterSecureStorage();

  static const _kBaseUrl = 'llm_base_url';
  static const _kApiKey = 'llm_api_key';
  static const _kModel = 'llm_model';

  static const defaultBaseUrl = 'https://api.deepseek.com/v1';
  static const defaultModel = 'deepseek-flash';

  Future<LlmConfig> load() async {
    final baseUrl =
        await _storage.read(key: _kBaseUrl) ?? defaultBaseUrl;
    final apiKey = await _storage.read(key: _kApiKey) ?? '';
    final model = await _storage.read(key: _kModel) ?? defaultModel;
    return LlmConfig(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }

  Future<void> save(LlmConfig config) async {
    await _storage.write(key: _kBaseUrl, value: config.baseUrl);
    await _storage.write(key: _kApiKey, value: config.apiKey);
    await _storage.write(key: _kModel, value: config.model);
  }
}
