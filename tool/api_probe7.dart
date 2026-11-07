// 探针 7：个人主页接口拿用户歌单列表
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
  var hash = 5381;
  for (final ch in keyst.codeUnits) {
    hash += (hash << 5) + ch;
  }
  final gtk = hash & 0x7fffffff;

  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
    'Cookie': cookie,
  };
  final c = http.Client();

  // ---------- A. fcg_get_profile_homepage ----------
  stdout.writeln('===== A. fcg_get_profile_homepage =====');
  try {
    final resp = await c.get(
      Uri.parse(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg'
        '?cv=4747474&ct=24&format=json&inCharset=utf8&outCharset=utf-8'
        '&notice=0&platform=yqq.json&needNewCode=0'
        '&uin=$uin&hostuin=$uin&g_tk=$gtk&loginUin=$uin',
      ),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final d = data['data'];
    stdout.writeln('data keys: ${d?.keys.toList()}');
    final create = d?['create'];
    if (create is Map) {
      stdout.writeln('create keys: ${create.keys.toList()}');
      final pl = create['playlist'];
      if (pl is Map) {
        stdout.writeln('playlist keys: ${pl.keys.toList()}');
        final list = pl['list'];
        if (list is List) {
          stdout.writeln('list count: ${list.length}');
          for (final item in list.take(10)) {
            if (item is Map) {
              stdout.writeln(
                  '  - tid=${item['tid']} name=${item['dirName'] ?? item['dissname']} '
                  'count=${item['song_count']} pic=${item['picurl'] ?? item['logo']}');
            }
          }
        }
      }
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- B. 收藏歌单（order asset 带 g_tk POST） ----------
  stdout.writeln('\n===== B. fcg_get_profile_order_asset with g_tk POST =====');
  try {
    final resp = await c.post(
      Uri.parse(
          'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_order_asset.fcg?cv=4747474&ct=24&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0&g_tk=$gtk'),
      headers: headers,
      body: {
        'uin': uin,
        'hostuin': uin,
        'pagenum': '0',
        'pagesize': '100',
      },
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final cdlist = data['data']?['cdlist'];
    stdout.writeln('cdlist=${cdlist is List ? cdlist.length : 'N/A'}');
    if (cdlist is List) {
      for (final cd in cdlist.take(5)) {
        stdout.writeln(
            '  - disstid=${cd['disstid']} name=${cd['dissname']} count=${cd['song_count']}');
      }
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  c.close();
}
