/// 歌曲与歌单的数据模型
class Song {
  final String name;
  final String artist;

  const Song({required this.name, required this.artist});

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      name: (json['name'] ?? '').toString().trim(),
      artist: (json['artist'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'artist': artist};
}

class Playlist {
  final String title;
  final String description;
  final List<Song> songs;

  const Playlist({
    required this.title,
    required this.description,
    required this.songs,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'];
    final songs = <Song>[];
    if (rawSongs is List) {
      for (final item in rawSongs) {
        if (item is Map) {
          songs.add(Song.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return Playlist(
      title: (json['title'] ?? '未命名歌单').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      songs: songs,
    );
  }
}
