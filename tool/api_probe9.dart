// 探针 9：复现匹配限流 — 匿名 vs 带登录态，连续搜索不同歌曲
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

  final queries = [
    '东风破 周杰伦',
    '波斯猫 S.H.E',
    'Super Star S.H.E',
    '不得不爱 潘玮柏',
    '快乐崇拜 潘玮柏',
    '隐形的翅膀 张韶涵',
    '欧若拉 张韶涵',
  ];

  final c = http.Client();

  // ---------- A. 匿名连续 7 次不同查询（模拟 app 当前行为） ----------
  stdout.writeln('===== A. anonymous, 7 different queries @ 500ms =====');
  final anonHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
  };
  for (final q in queries) {
    try {
      final body = {
        'req_1': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicDesktop',
          'param': {
            'query': q,
            'num_per_page': 5,
            'page_num': 1,
            'search_type': 0,
            'grp': 1,
          },
        },
      };
      final resp = await c
          .post(
            Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
            headers: {...anonHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = data['req_1']?['data']?['body']?['song']?['list'];
      final code = data['req_1']?['code'];
      stdout.writeln(
          '  $q -> code=$code count=${list is List ? list.length : 'X'}');
    } catch (e) {
      stdout.writeln('  $q -> FAILED: $e');
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ---------- B. 带登录态（Cookie + comm.authst）连续 7 次 ----------
  stdout.writeln('\n===== B. with login cookie, same 7 queries =====');
  final authedHeaders = {
    ...anonHeaders,
    'Cookie': cookie,
  };
  for (final q in queries) {
    try {
      final body = {
        'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
        'req_1': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicDesktop',
          'param': {
            'query': q,
            'num_per_page': 5,
            'page_num': 1,
            'search_type': 0,
            'grp': 1,
          },
        },
      };
      final resp = await c
          .post(
            Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
            headers: {...authedHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = data['req_1']?['data']?['body']?['song']?['list'];
      final code = data['req_1']?['code'];
      stdout.writeln(
          '  $q -> code=$code count=${list is List ? list.length : 'X'}');
    } catch (e) {
      stdout.writeln('  $q -> FAILED: $e');
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  c.close();
}
