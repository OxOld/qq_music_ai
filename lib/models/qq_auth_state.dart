/// QQ 音乐登录态（纯数据类）
///
/// 从 `qq_music_client.dart` 拆出，供 client / auth service / provider 共用，
/// 避免 provider 层 import client 时形成循环依赖。
class QQAuthState {
  final String cookie;
  final String uin;
  final String skey;
  final String musickey;

  const QQAuthState({
    this.cookie = '',
    this.uin = '',
    this.skey = '',
    this.musickey = '',
  });

  bool get isLoggedIn => cookie.isNotEmpty && uin.isNotEmpty;

  /// 从 Cookie 字符串解析登录态（兼容 QQ 登录 / 微信登录的多种字段）
  factory QQAuthState.fromCookie(String cookie) {
    String extract(String key) {
      for (final part in cookie.split(';')) {
        final trimmed = part.trim();
        final eq = trimmed.indexOf('=');
        if (eq > 0 && trimmed.substring(0, eq) == key) {
          return trimmed.substring(eq + 1);
        }
      }
      return '';
    }

    // uin：优先 uin，其次 p_uin（网页登录），再次 wxuin（微信）
    var uin = extract('uin');
    if (uin.isEmpty) uin = extract('p_uin');
    if (uin.isEmpty) uin = extract('wxuin');
    // QQ 号常带 o0 前缀，如 uin=o0123456789
    if (uin.startsWith('o0')) {
      uin = uin.substring(2);
    } else if (uin.startsWith('o')) {
      uin = uin.substring(1);
    }

    // skey：优先 skey，其次 p_skey，再次 wxskey
    var skey = extract('skey');
    if (skey.isEmpty) skey = extract('p_skey');
    if (skey.isEmpty) skey = extract('wxskey');

    // musickey：qm_keyst / qqmusic_key（musicu 写接口的 authst）
    var musickey = extract('qm_keyst');
    if (musickey.isEmpty) musickey = extract('qqmusic_key');

    return QQAuthState(
      cookie: cookie,
      uin: uin,
      skey: skey,
      musickey: musickey,
    );
  }
}
