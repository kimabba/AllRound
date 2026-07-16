import 'package:allround/models/club_post.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> postJson({
  String tag = 'free',
  String? authorId = 'user-1',
  String? authorName = '회원',
}) {
  return {
    'id': 'post-1',
    'club_id': 'club-1',
    'author_id': authorId,
    'users': authorName == null ? null : {'name': authorName},
    'tag': tag,
    'title': '게시글 제목',
    'body': '게시글 내용',
    'image_urls': <String>[],
    'is_pinned': false,
    'created_at': '2026-07-15T00:00:00Z',
    'updated_at': '2026-07-15T00:00:00Z',
    'club_post_comments': <Object>[],
  };
}

void main() {
  test('일반 게시글은 댓글을 허용한다', () {
    for (final tag in ['free', 'recruit', 'photo']) {
      expect(ClubPost.fromJson(postJson(tag: tag)).allowsComments, isTrue);
    }
  });

  test('공지사항은 댓글을 허용하지 않는다', () {
    final post = ClubPost.fromJson(postJson(tag: 'notice'));

    expect(post.allowsComments, isFalse);
  });

  test('알 수 없는 게시글 종류도 댓글을 허용하지 않는다', () {
    final post = ClubPost.fromJson(postJson(tag: 'event'));

    expect(post.allowsComments, isFalse);
  });

  test('탈퇴한 게시글·댓글 작성자를 안전하게 표시한다', () {
    final post = ClubPost.fromJson(
      postJson(authorId: null, authorName: null),
    );
    final comment = ClubPostComment.fromJson({
      'id': 'comment-1',
      'post_id': 'post-1',
      'author_id': null,
      'users': null,
      'body': '댓글',
      'created_at': '2026-07-15T00:00:00Z',
    });

    expect(post.authorDisplayName, '탈퇴한 사용자');
    expect(comment.authorDisplayName, '탈퇴한 사용자');
  });
}
