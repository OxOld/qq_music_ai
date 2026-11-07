// 带真实登录态的全接口实测探针
// 运行: dart run tool/api_probe4.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final cookie = File('tool/test_cookie.txt').readAsStringSync().trim();
  // 从 cookie 提取 uin 和 qm_keyst
  String extract(String key) {
    for (final part in cookie.split(';')) {
      final t = part.trim();
      final eq = t.indexOf('=');
      if (eq > 0 && t.substring(0, eq) == key) return t.substring(eq + 1);
    }
    return '';
  }

  final uin = extract('uin');
  final keyst = extract('qm_keyst');
  final gtk = _gtk(keyst);
  stdout.writeln('uin=$uin, keyst=${keyst.substring(0, 12)}..., g_tk=$gtk');

  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
    'Cookie': cookie,
  };
  final c = http.Client();

  // ---------- 1. 我创建的歌单（老 fcgi） ----------
  stdout.writeln('\n===== 1. fcg_user_created_diss =====');
  try {
    final resp = await c.get(
      Uri.parse(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss?cv=4747474'
        '&ct=24&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
        '&platform=yqq.json&needNewCode=0&uin=$uin&hostuin=$uin'
        '&g_tk=$gtk&loginUin=$uin',
      ),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    stdout.writeln('HTTP ${resp.statusCode}, len=${body.length}');
    final data = jsonDecode(body);
    final cdlist = data['data']?['cdlist'];
    if (cdlist is List) {
      stdout.writeln('cdlist count: ${cdlist.length}');
      for (final cd in cdlist.take(8)) {
        stdout.writeln(
            '  - disstid=${cd['disstid']} dirid=${cd['dirid']} '
            'name=${cd['dissname']} count=${cd['song_count']}');
      }
    } else {
      stdout.writeln('body head: ${body.substring(0, body.length > 300 ? 300 : body.length)}');
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 2. 收藏歌单 ----------
  stdout.writeln('\n===== 2. fcg_get_profile_order_asset =====');
  try {
    final resp = await c.get(
      Uri.parse(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_order_asset.fcg'
        '?cv=4747474&ct=24&format=json&inCharset=utf8&outCharset=utf-8'
        '&notice=0&platform=yqq.json&needNewCode=0&uin=$uin&hostuin=$uin'
        '&g_tk=$gtk&loginUin=$uin',
      ),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final cdlist = data['data']?['cdlist'];
    stdout.writeln(
        'HTTP ${resp.statusCode}, cdlist=${cdlist is List ? cdlist.length : 'N/A'}');
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 3. CgiGetDiss 歌单详情（dirid:201 我喜欢） ----------
  stdout.writeln('\n===== 3. CgiGetDiss dirid:201 (我喜欢) =====');
  try {
    final resp = await c.post(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
        'req_1': {
          'module': 'music.srfDissInfo.DissInfo',
          'method': 'CgiGetDiss',
          'param': {
            'disstid': 0,
            'dirid': 201,
            'song_begin': 0,
            'song_num': 10,
            'userinfo': true,
            'orderlist': true,
          },
        },
      }),
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final req = data['req_1'];
    final dirinfo = req?['data']?['dirinfo'];
    final songlist = req?['data']?['songlist'];
    stdout.writeln('code=${req?['code']} title=${dirinfo?['title']} '
        'total=${dirinfo?['song_total_num']} songs=${songlist is List ? songlist.length : 0}');
    if (songlist is List && songlist.isNotEmpty) {
      final s0 = songlist.first;
      stdout.writeln('  first: mid=${s0['mid']} id=${s0['id']} '
          'name=${s0['name']}');
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 4. 创建歌单（AddPlaylist） ----------
  stdout.writeln('\n===== 4. PlaylistBaseWrite / AddPlaylist =====');
  int? newDirId;
  try {
    final resp = await c.post(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
        'req_1': {
          'module': 'music.musicasset.PlaylistBaseWrite',
          'method': 'AddPlaylist',
          'param': {
            'dirName': 'AI测试歌单-${DateTime.now().millisecondsSinceEpoch % 10000}',
            'dirDesc': '',
            'dirPicUrl': '',
            'taglist': '',
            'dirShow': 2,
          },
        },
      }),
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    stdout.writeln('body: ${body.length > 500 ? body.substring(0, 500) : body}');
    final data = jsonDecode(body);
    final req = data['req_1'];
    final d = req?['data'];
    stdout.writeln('code=${req?['code']} retCode=${d?['retCode']} '
        'dirId=${d?['dirId']} tid=${d?['tid']}');
    newDirId =
        (d?['dirId'] ?? d?['tid'] ?? d?['dirid']) is int
            ? (d?['dirId'] ?? d?['tid'] ?? d?['dirid']) as int
            : int.tryParse('${d?['dirId'] ?? d?['tid'] ?? ''}');
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 5. 搜索拿 songId 并加歌 ----------
  stdout.writeln('\n===== 5. search + AddSonglist =====');
  if (newDirId != null) {
    try {
      final resp = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'req_1': {
            'module': 'music.search.SearchCgiService',
            'method': 'DoSearchForQQMusicDesktop',
            'param': {
              'query': '晴天 周杰伦',
              'num_per_page': 1,
              'page_num': 1,
              'search_type': 0,
              'grp': 1,
            },
          },
        }),
      ).timeout(const Duration(seconds: 15));
      final song = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['req_1']
              ?['data']?['body']?['song']?['list']?[0] as Map?;
      final songId = song?['id'];
      final songMid = song?['mid'];
      stdout.writeln('search: id=$songId mid=$songMid name=${song?['name']}');

      final resp2 = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
          'req_1': {
            'module': 'music.musicasset.PlaylistDetailWrite',
            'method': 'AddSonglist',
            'param': {
              'dirId': newDirId,
              'tid': newDirId,
              'bFmtUtf8': true,
              'v_songInfo': [
                {'songId': songId, 'songType': 0},
              ],
            },
          },
        }),
      ).timeout(const Duration(seconds: 15));
      final body2 = utf8.decode(resp2.bodyBytes);
      stdout.writeln('add: ${body2.length > 400 ? body2.substring(0, 400) : body2}');
    } catch (e) {
      stdout.writeln('FAILED: $e');
    }
  }

  // ---------- 6. 带登录的播放链接 ----------
  stdout.writeln('\n===== 6. vkey with login =====');
  try {
    final resp = await c.post(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'comm': {'ct': 19, 'cv': 0, 'uin': uin, 'authst': keyst},
        'req_1': {
          'module': 'vkey.GetVkeyServer',
          'method': 'CgiGetVkey',
          'param': {
            'guid': '10000',
            'songmid': ['0039MnYb0qxYhV'],
            'songtype': [0],
            'uin': uin,
            'loginflag': 1,
            'platform': '20',
          },
        },
      }),
    ).timeout(const Duration(seconds: 15));
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final info = data['req_1']?['data']?['midurlinfo']?[0];
    final sip = data['req_1']?['data']?['sip'];
    stdout.writeln('sip: $sip');
    stdout.writeln('purl: ${info?['purl']}');
    final purl = info?['purl']?.toString() ?? '';
    if (purl.isNotEmpty) {
      final prefix = sip is List && sip.isNotEmpty ? sip.first.toString() : '';
      final url = '$prefix$purl';
      stdout.writeln('full: ${url.substring(0, url.length > 120 ? 120 : url.length)}');
      final head = await c.head(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));
      stdout.writeln('HEAD: ${head.statusCode}');
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  c.close();
}

int _gtk(String skey) {
  if (skey.isEmpty) return 0;
  var hash = 5381;
  for (final ch in skey.codeUnits) {
    hash += (hash << 5) + ch;
  }
  return hash & 0x7fffffff;
}
