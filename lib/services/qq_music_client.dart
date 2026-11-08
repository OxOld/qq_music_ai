import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/qq_song.dart';

/// QQ 音乐登录态
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

    // uin：优先 uin，其次 p_uin（网页登录），其次 wxuin（微信）
    var uin = extract('uin');
    if (uin.isEmpty) uin = extract('p_uin');
    if (uin.isEmpty) uin = extract('wxuin');
    // QQ 号常带 o0 前缀，如 uin=o0123456789
    if (uin.startsWith('o0')) {
      uin = uin.substring(2);
    } else if (uin.startsWith('o')) {
      uin = uin.substring(1);
    }

    // skey：优先 skey，其次 p_skey，其次 wxskey
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

/// 腾讯 g_tk 算法（基于 skey）
int _getGTK(String skey) {
  if (skey.isEmpty) return 0;
  var hash = 5381;
  for (final c in skey.codeUnits) {
    hash += (hash << 5) + c;
  }
  return hash & 0x7fffffff;
}

/// QQ 音乐客户端 —— 纯本地解析，直连官方接口（无网关）
///
/// 接口形状均经真实登录态实测（见 tool/api_probe*.dart）：
/// - 我的歌单：fcg_user_created_diss（创建）+ fcg_get_profile_order_asset（收藏）
/// - 歌单歌曲：musicu CgiGetDiss
/// - 创建歌单：musicu AddPlaylist（GBK 响应，返回 dirId 内部 + tid 对外）
/// - 添加歌曲：musicu AddSonglist（用数字 songId + 内部 dirId）
/// - 播放链接：vkey CgiGetVkey（sip 为 http，已放行明文并优先替换 https）
class QQMusicClient {
  QQMusicClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
  };

  /// 个人主页相关的老 fcgi 需要 profile 页 Referer
  static final Map<String, String> _profileHeaders = {
    ..._headers,
    'Referer': 'https://y.qq.com/portal/profile.html',
  };

  Map<String, String> _authedHeaders(QQAuthState auth) => {
    ..._headers,
    'Content-Type': 'application/json',
    'Cookie': auth.cookie,
  };

  /// musicu.fcg 响应可能因中文参数返回 GBK，先 UTF-8 再 latin1 兜底
  String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  // ---------- 搜索 ----------

  /// 搜索歌曲。传入登录态时走账号维度（移动网络下更不容易被限流）
  Future<List<QQSong>> search(
    String keyword, {
    int limit = 20,
    QQAuthState? auth,
  }) async {
    final url = Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg');
    final loggedIn = auth != null && auth.isLoggedIn;
    final body = {
      if (loggedIn)
        'comm': {
          'ct': 24,
          'cv': 4747474,
          'uin': auth.uin,
          'authst': auth.musickey,
        },
      'req_1': {
        'module': 'music.search.SearchCgiService',
        'method': 'DoSearchForQQMusicDesktop',
        'param': {
          'query': keyword,
          'num_per_page': limit,
          'page_num': 1,
          'search_type': 0,
          'grp': 1,
        },
      },
    };

    final resp = await _client
        .post(
          url,
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
            if (loggedIn) 'Cookie': auth.cookie,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw QQMusicException('搜索失败 (${resp.statusCode})');
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final list = _digList(data, ['req_1', 'data', 'body', 'song', 'list']);

    return list
        .whereType<Map>()
        .map((e) => QQSong.fromSearchJson(Map<String, dynamic>.from(e)))
        .where((s) => s.mid.isNotEmpty && s.name.isNotEmpty)
        .toList();
  }

  // ---------- 我的歌单 ----------

  /// 登录用户的歌单（创建的 + 收藏的），「我喜欢」置顶
  Future<List<MyPlaylist>> getMyPlaylists(QQAuthState auth) async {
    final gtk = _getGTK(auth.musickey.isNotEmpty ? auth.musickey : auth.skey);
    final result = <MyPlaylist>[];

    // 1) 创建的歌单
    try {
      final resp = await _client
          .get(
            Uri.parse(
              'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss'
              '?hostUin=0&hostuin=${auth.uin}&sin=0&size=200&g_tk=$gtk'
              '&loginUin=${auth.uin}&format=json&inCharset=utf8'
              '&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0',
            ),
            headers: {..._profileHeaders, 'Cookie': auth.cookie},
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = data['data']?['disslist'];
      if (list is List) {
        for (final item in list.whereType<Map>()) {
          // dir_show == 0 为隐藏歌单（如 QZone 背景音乐）
          if ((item['dir_show'] ?? 1) == 0) continue;
          final tid = item['tid']?.toString() ?? '';
          final dirid = item['dirid']?.toString() ?? '';
          if (tid == '0' && dirid.isEmpty) continue;
          result.add(
            MyPlaylist(
              id: tid.isNotEmpty && tid != '0' ? tid : dirid,
              dirId: int.tryParse(dirid) ?? 0,
              name: item['diss_name']?.toString() ?? '未命名歌单',
              count: (item['song_cnt'] as num?)?.toInt() ?? 0,
              coverUrl: _https(item['diss_cover']?.toString()),
              isCreated: true,
            ),
          );
        }
      }
    } catch (_) {
      // 创建列表失败不影响收藏列表
    }

    // 2) 收藏的歌单
    try {
      final resp = await _client
          .get(
            Uri.parse(
              'https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg'
              '?ct=20&cid=205360956&userid=${auth.uin}&reqtype=3&sin=0&ein=80'
              '&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
              '&platform=yqq.json&needNewCode=0&g_tk=$gtk&loginUin=${auth.uin}'
              '&hostUin=0&uin=${auth.uin}',
            ),
            headers: {..._profileHeaders, 'Cookie': auth.cookie},
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = data['data']?['cdlist'];
      if (list is List) {
        for (final item in list.whereType<Map>()) {
          final id = item['dissid']?.toString() ?? '';
          if (id.isEmpty) continue;
          result.add(
            MyPlaylist(
              id: id,
              dirId: int.tryParse(item['dirid']?.toString() ?? '') ?? 0,
              name: item['dissname']?.toString() ?? '未命名歌单',
              count: (item['songnum'] as num?)?.toInt() ?? 0,
              coverUrl: _https(item['logo']?.toString()),
              isCreated: false,
            ),
          );
        }
      }
    } catch (_) {}

    if (result.isEmpty) {
      throw const QQMusicException('获取我的歌单失败：请尝试重新登录');
    }

    // 去重 + 「我喜欢」置顶
    final seen = <String>{};
    final unique = result.where((p) {
      if (seen.contains(p.id)) return false;
      seen.add(p.id);
      return true;
    }).toList();
    unique.sort((a, b) => (a.id == '201' ? 0 : 1) - (b.id == '201' ? 0 : 1));
    return unique;
  }

  // ---------- 歌单详情 ----------

  /// 歌单内的歌曲。[playlistId] 为对外歌单 ID（tid / dissid）。
  Future<List<QQSong>> getPlaylistSongs(
    QQAuthState auth,
    String playlistId,
  ) async {
    final isLiked = playlistId == '201';
    final param = isLiked
        ? {
            'disstid': 0,
            'dirid': 201,
            'song_begin': 0,
            'song_num': 500,
            'userinfo': true,
            'orderlist': true,
          }
        : {
            'disstid': int.tryParse(playlistId) ?? 0,
            'song_begin': 0,
            'song_num': 500,
            'userinfo': true,
            'orderlist': true,
          };

    final resp = await _client
        .post(
          Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: _authedHeaders(auth),
          body: jsonEncode({
            'comm': {
              'ct': 24,
              'cv': 4747474,
              'uin': auth.uin,
              'authst': auth.musickey,
            },
            'req_1': {
              'module': 'music.srfDissInfo.DissInfo',
              'method': 'CgiGetDiss',
              'param': param,
            },
          }),
        )
        .timeout(const Duration(seconds: 20));

    final data = jsonDecode(_decode(resp.bodyBytes));
    final req = data['req_1'];
    if (req is! Map || req['code'] != 0) {
      throw QQMusicException('获取歌单歌曲失败 code=${req?['code']}');
    }
    final list = req['data']?['songlist'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => QQSong.fromSearchJson(Map<String, dynamic>.from(e)))
        .where((s) => s.mid.isNotEmpty && s.name.isNotEmpty)
        .toList();
  }

  // ---------- 写接口（需登录态） ----------

  /// 创建歌单，返回内部 dirId（加歌用）。
  /// 对外展示用 tid，通过返回的 MyPlaylist.id 提供。
  Future<CreatePlaylistResult> createPlaylist(
    QQAuthState auth,
    String name,
  ) async {
    final resp = await _client
        .post(
          Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: _authedHeaders(auth),
          body: jsonEncode({
            'comm': {
              'ct': 24,
              'cv': 4747474,
              'uin': auth.uin,
              'authst': auth.musickey,
            },
            'req_1': {
              'module': 'music.musicasset.PlaylistBaseWrite',
              'method': 'AddPlaylist',
              'param': {
                'dirName': name,
                'dirDesc': '',
                'dirPicUrl': '',
                'taglist': '',
                'dirShow': 2,
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 20));

    // 响应可能为 GBK（中文 dirName 回显），latin1 兜底保证数字字段可解析
    final body = _decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final req = data['req_1'];
    if (req is! Map || req['code'] != 0) {
      throw QQMusicException('创建歌单失败 code=${req?['code']}');
    }
    final d = req['data'];
    final retCode = d?['retCode'];
    if (retCode != 0) {
      throw QQMusicException('创建歌单被拒绝 (retCode=$retCode)');
    }
    final dirId =
        int.tryParse('${d?['result']?['dirId'] ?? d?['dirId'] ?? ''}') ?? 0;
    final tid = int.tryParse('${d?['result']?['tid'] ?? d?['tid'] ?? ''}') ?? 0;
    if (dirId == 0 && tid == 0) {
      throw QQMusicException('创建歌单失败：响应中无歌单 ID');
    }
    return CreatePlaylistResult(dirId: dirId, tid: tid);
  }

  /// 批量添加歌曲到歌单（[dirId] 为创建歌单返回的内部 ID）
  Future<bool> addSongsToPlaylist(
    QQAuthState auth,
    int dirId,
    List<QQSong> songs,
  ) async {
    for (var i = 0; i < songs.length; i += 50) {
      final batch = songs.sublist(
        i,
        i + 50 > songs.length ? songs.length : i + 50,
      );
      final resp = await _client
          .post(
            Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
            headers: _authedHeaders(auth),
            body: jsonEncode({
              'comm': {
                'ct': 24,
                'cv': 4747474,
                'uin': auth.uin,
                'authst': auth.musickey,
              },
              'req_1': {
                'module': 'music.musicasset.PlaylistDetailWrite',
                'method': 'AddSonglist',
                'param': {
                  'dirId': dirId,
                  'tid': dirId,
                  'bFmtUtf8': true,
                  'v_songInfo': [
                    for (final s in batch) {'songId': s.songId, 'songType': 0},
                  ],
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = _decode(resp.bodyBytes);
      final data = jsonDecode(body);
      final req = data['req_1'];
      if (req is! Map || req['code'] != 0) {
        throw QQMusicException('添加歌曲失败 code=${req?['code']}');
      }
      final retCode = req['data']?['retCode'];
      if (retCode != 0) {
        throw QQMusicException('添加歌曲被拒绝 (retCode=$retCode)');
      }
    }
    return true;
  }

  /// 批量从我创建的歌单移除歌曲（DelSonglist，与 AddSonglist 同模块对称）
  Future<bool> removeSongsFromPlaylist(
    QQAuthState auth,
    int dirId,
    List<QQSong> songs,
  ) async {
    for (var i = 0; i < songs.length; i += 50) {
      final batch = songs.sublist(
        i,
        i + 50 > songs.length ? songs.length : i + 50,
      );
      final resp = await _client
          .post(
            Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
            headers: _authedHeaders(auth),
            body: jsonEncode({
              'comm': {
                'ct': 24,
                'cv': 4747474,
                'uin': auth.uin,
                'authst': auth.musickey,
              },
              'req_1': {
                'module': 'music.musicasset.PlaylistDetailWrite',
                'method': 'DelSonglist',
                'param': {
                  'dirId': dirId,
                  'tid': dirId,
                  'bFmtUtf8': true,
                  'v_songInfo': [
                    for (final s in batch) {'songId': s.songId, 'songType': 0},
                  ],
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = _decode(resp.bodyBytes);
      final data = jsonDecode(body);
      final req = data['req_1'];
      if (req is! Map || req['code'] != 0) {
        throw QQMusicException('移除歌曲失败 code=${req?['code']}');
      }
      final retCode = req['data']?['retCode'];
      if (retCode != 0) {
        throw QQMusicException('移除歌曲被拒绝 (retCode=$retCode)');
      }
    }
    return true;
  }

  /// 删除我创建的歌单（实测可用）
  Future<void> deletePlaylist(QQAuthState auth, {required int dirId}) async {
    final resp = await _client
        .post(
          Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: _authedHeaders(auth),
          body: jsonEncode({
            'comm': {
              'ct': 24,
              'cv': 4747474,
              'uin': auth.uin,
              'authst': auth.musickey,
            },
            'req_1': {
              'module': 'music.musicasset.PlaylistBaseWrite',
              'method': 'DelPlaylist',
              'param': {'dirId': dirId},
            },
          }),
        )
        .timeout(const Duration(seconds: 20));

    final body = _decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final req = data['req_1'];
    if (req is! Map || req['code'] != 0) {
      throw QQMusicException('删除歌单失败 code=${req?['code']}');
    }
    if (req['data']?['retCode'] != 0) {
      throw QQMusicException(
        '删除被拒绝 (retCode=${req['data']?['retCode']}，系统歌单不可删除)',
      );
    }
  }

  /// 重命名歌单。
  ///
  /// 官方未开放独立改名接口，采用「读歌 → 新名重建 → 迁移歌曲 → 删旧歌单」
  /// 的组合实现（全部为已验证接口）。注意：歌单 tid 会变化。
  Future<void> renamePlaylist(
    QQAuthState auth, {
    required MyPlaylist playlist,
    required String newName,
  }) async {
    if (playlist.dirId <= 0) {
      throw const QQMusicException('该歌单不支持重命名');
    }
    final songs = await getPlaylistSongs(auth, playlist.id);
    final created = await createPlaylist(auth, newName);
    if (songs.isNotEmpty) {
      await addSongsToPlaylist(auth, created.dirId, songs);
    }
    await deletePlaylist(auth, dirId: playlist.dirId);
  }

  // ---------- 播放链接 ----------

  /// 播放链接本地缓存（本地优先，同正版）：mid -> {url, ts}
  /// vkey 有时效（约数小时），缓存 TTL 取保守的 60 分钟
  static const _urlCacheKey = 'play_url_cache';
  static const _urlCacheTtl = Duration(minutes: 60);
  final Map<String, Map<String, dynamic>> _urlCache = {};
  bool _urlCacheLoaded = false;

  Future<void> _ensureUrlCache() async {
    if (_urlCacheLoaded) return;
    _urlCacheLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_urlCacheKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              _urlCache[k.toString()] = Map<String, dynamic>.from(v);
            }
          });
        }
      }
    } catch (_) {}
  }

  /// 缓存有效（未过期）则返回链接，否则 null
  String? _cachedPlayUrl(String songmid) {
    final entry = _urlCache[songmid];
    if (entry == null) return null;
    final ts = (entry['ts'] as num?)?.toInt() ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age < 0 || age > _urlCacheTtl.inMilliseconds) {
      _urlCache.remove(songmid);
      return null;
    }
    final url = entry['url']?.toString() ?? '';
    return url.isEmpty ? null : url;
  }

  Future<void> _cachePlayUrl(String songmid, String url) async {
    _urlCache[songmid] = {
      'url': url,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      // 顺手清掉过期项，避免无限增长
      final now = DateTime.now().millisecondsSinceEpoch;
      _urlCache.removeWhere(
        (_, v) =>
            now - ((v['ts'] as num?)?.toInt() ?? 0) >
            _urlCacheTtl.inMilliseconds,
      );
      await prefs.setString(_urlCacheKey, jsonEncode(_urlCache));
    } catch (_) {}
  }

  /// 获取歌曲播放链接（本地优先：缓存未过期直接用）。
  /// sip 前缀统一替换为 https（实测可用）。
  Future<String> getPlayUrl(QQAuthState auth, String songmid) async {
    await _ensureUrlCache();
    final cached = _cachedPlayUrl(songmid);
    if (cached != null) return cached;

    final url = Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg');
    final body = {
      'comm': {'ct': 19, 'cv': 0, 'uin': auth.uin, 'authst': auth.musickey},
      'req_1': {
        'module': 'vkey.GetVkeyServer',
        'method': 'CgiGetVkey',
        'param': {
          'guid': '10000',
          'songmid': [songmid],
          'songtype': [0],
          'uin': auth.uin,
          'loginflag': 1,
          'platform': '20',
        },
      },
    };

    final resp = await _client
        .post(url, headers: _authedHeaders(auth), body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw QQMusicException('获取播放链接失败 (${resp.statusCode})');
    }
    final data = jsonDecode(_decode(resp.bodyBytes));
    final midurlinfo = _digList(data, ['req_1', 'data', 'midurlinfo']);
    if (midurlinfo.isEmpty) {
      throw const QQMusicException('该歌曲暂无播放链接');
    }
    final purl = (midurlinfo.first as Map)['purl']?.toString() ?? '';
    if (purl.isEmpty) {
      throw const QQMusicException('该歌曲暂无播放链接（可能为会员/版权限制）');
    }
    final prefix = (midurlinfo.first as Map)['sip'] is List
        ? ((midurlinfo.first['sip'] as List).isNotEmpty
              ? (midurlinfo.first['sip'] as List).first.toString()
              : 'http://ws.stream.qqmusic.qq.com/')
        : 'http://ws.stream.qqmusic.qq.com/';
    // sip 为 http，实测 https 同样可用（HEAD 200），统一升级
    final full = '$prefix$purl'.replaceFirst('http://', 'https://');
    unawaited(_cachePlayUrl(songmid, full));
    return full;
  }

  // ---------- 工具 ----------

  String? _https(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'https://');
    }
    return url;
  }

  List<dynamic> _digList(dynamic root, List<dynamic> keys) {
    dynamic cur = root;
    for (final k in keys) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return const [];
      }
    }
    return cur is List ? cur : const [];
  }
}

class QQMusicException implements Exception {
  final String message;
  const QQMusicException(this.message);

  @override
  String toString() => message;
}

/// 我（登录用户）的歌单
class MyPlaylist {
  /// 对外歌单 ID（tid / dissid），详情查询用；「我喜欢」固定为 201
  final String id;

  /// 内部 dirId（创建的歌单加歌时用）
  final int dirId;
  final String name;
  final int count;
  final String? coverUrl;

  /// true = 我创建的歌单（可加歌）；false = 收藏的歌单（别人的，不可加歌）
  final bool isCreated;

  const MyPlaylist({
    required this.id,
    required this.name,
    required this.count,
    this.dirId = 0,
    this.coverUrl,
    this.isCreated = false,
  });
}

/// 创建歌单的结果：dirId 用于加歌，tid 用于对外展示
class CreatePlaylistResult {
  final int dirId;
  final int tid;

  const CreatePlaylistResult({required this.dirId, required this.tid});
}
