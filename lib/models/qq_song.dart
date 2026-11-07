/// QQ 音乐歌曲模型（搜索结果 / 歌单歌曲）
class QQSong {
  final String mid;
  final int songId; // 数字 ID（写接口 AddSonglist 需要）
  final String name;
  final String artist;
  final String album;
  final String? coverUrl;

  const QQSong({
    required this.mid,
    required this.songId,
    required this.name,
    required this.artist,
    required this.album,
    this.coverUrl,
  });

  factory QQSong.fromSearchJson(Map<String, dynamic> json) {
    final singers = json['singer'];
    final artist = singers is List && singers.isNotEmpty
        ? singers.map((s) => s['name']?.toString() ?? '').join('/')
        : '';
    final album = json['album'];
    final albumName = album is Map ? (album['name']?.toString() ?? '') : '';
    final albumMid = album is Map ? album['mid']?.toString() : null;

    return QQSong(
      mid: json['mid']?.toString() ?? '',
      songId: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? json['title']?.toString() ?? '',
      artist: artist,
      album: albumName,
      coverUrl: albumMid != null
          ? 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg'
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'mid': mid,
        'songId': songId,
        'name': name,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
      };
}
