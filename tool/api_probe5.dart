// 探针 5：修歌单列表分页 + 创建歌单编码问题
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final cookie = File('tool/test_cookie.txt').readAsStringSync().trim();
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

  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
    'Cookie': cookie,
  };
  final c = http.Client();

  // ---------- 1. 我的歌单（带分页参数） ----------
  stdout.writeln('===== 1. fcg_user_created_diss with paging =====');
  try {
    final resp = await c.get(
      Uri.parse(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss?cv=4747474'
        '&ct=24&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
        '&platform=yqq.json&needNewCode=0&uin=$uin&hostuin=$uin'
        '&g_tk=$gtk&loginUin=$uin&pagenum=0&pagesize=100',
      ),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final d = data['data'];
    stdout.writeln('keys: ${d?.keys.toList()}');
    final list = d?['disslist'] ?? d?['cdlist'];
    if (list is List) {
      stdout.writeln('count: ${list.length}');
      for (final cd in list.take(10)) {
        stdout.writeln(
            '  - ${cd is Map ? 'disstid=${cd['disstid']} dirid=${cd['dirid']} name=${cd['dissname'] ?? cd['dirName']} count=${cd['song_count'] ?? cd['songnum']}' : cd}');
      }
    } else {
      stdout.writeln('body: ${body.substring(0, body.length > 400 ? 400 : body.length)}');
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 2. 创建歌单（latin1 解码诊断） ----------
  stdout.writeln('\n===== 2. AddPlaylist encoding diagnose =====');
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
            'dirName': 'AI歌单测试_${DateTime.now().millisecondsSinceEpoch % 10000}',
            'dirDesc': '',
            'dirPicUrl': '',
            'taglist': '',
            'dirShow': 2,
          },
        },
      }),
    ).timeout(const Duration(seconds: 15));
    final bytes = resp.bodyBytes;
    stdout.writeln('bytes len=${bytes.length}');
    // 尝试 latin1 解码（永不失败）
    final asLatin = latin1.decode(bytes, allowInvalid: true);
    stdout.writeln('latin1: ${asLatin.length > 500 ? asLatin.substring(0, 500) : asLatin}');
    // 提取 dirId
    final m = RegExp(r'"(dirId|tid|dirid)"\s*:\s*(\d+)').firstMatch(asLatin);
    if (m != null) {
      newDirId = int.parse(m.group(2)!);
      stdout.writeln('newDirId=$newDirId');
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 3. 加歌 ----------
  if (newDirId != null) {
    stdout.writeln('\n===== 3. AddSonglist to $newDirId =====');
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
      stdout.writeln('songId=$songId name=${song?['name']}');

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
      final asLatin = latin1.decode(resp2.bodyBytes, allowInvalid: true);
      stdout.writeln('add resp: ${asLatin.length > 400 ? asLatin.substring(0, 400) : asLatin}');
    } catch (e) {
      stdout.writeln('FAILED: $e');
    }
  }

  // ---------- 4. https 播放流测试 ----------
  stdout.writeln('\n===== 4. https stream test =====');
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
    final purl = info?['purl']?.toString() ?? '';
    if (purl.isNotEmpty) {
      final httpsUrl = 'https://aqqmusic.tc.qq.com/$purl';
      try {
        final head = await c.head(Uri.parse(httpsUrl), headers: headers)
            .timeout(const Duration(seconds: 10));
        stdout.writeln('HTTPS HEAD: ${head.statusCode} '
            'len=${head.headers['content-length']}');
      } catch (e) {
        stdout.writeln('HTTPS HEAD FAILED: $e');
      }
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
