class ClubPost {
  final String id;
  final String clubId;
  final String authorId;
  final String? authorName;
  final String tag; // notice, free, recruit, photo
  final String title;
  final String body;
  final List<String> imageUrls;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int commentCount;

  const ClubPost({
    required this.id,
    required this.clubId,
    required this.authorId,
    this.authorName,
    required this.tag,
    required this.title,
    required this.body,
    this.imageUrls = const [],
    required this.createdAt,
    required this.updatedAt,
    this.commentCount = 0,
  });

  factory ClubPost.fromJson(Map<String, dynamic> j) {
    final author = j['users'] as Map<String, dynamic>?;
    final comments = j['club_post_comments'] as List?;
    return ClubPost(
      id: j['id'] as String,
      clubId: j['club_id'] as String,
      authorId: j['author_id'] as String,
      authorName: author?['name'] as String?,
      tag: j['tag'] as String,
      title: j['title'] as String,
      body: j['body'] as String,
      imageUrls: (j['image_urls'] as List?)?.cast<String>() ?? const [],
      createdAt: DateTime.parse(j['created_at'] as String),
      updatedAt: DateTime.parse(j['updated_at'] as String),
      commentCount: comments?.length ?? 0,
    );
  }

  String get tagLabel => switch (tag) {
    'notice' => '공지',
    'free' => '자유',
    'recruit' => '모집',
    'photo' => '사진',
    _ => tag,
  };
}

class ClubPostComment {
  final String id;
  final String postId;
  final String authorId;
  final String? authorName;
  final String body;
  final DateTime createdAt;

  const ClubPostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.authorName,
    required this.body,
    required this.createdAt,
  });

  factory ClubPostComment.fromJson(Map<String, dynamic> j) {
    final author = j['users'] as Map<String, dynamic>?;
    return ClubPostComment(
      id: j['id'] as String,
      postId: j['post_id'] as String,
      authorId: j['author_id'] as String,
      authorName: author?['name'] as String?,
      body: j['body'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
}
