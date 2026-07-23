import 'package:allround/screens/clubs/widgets/club_intro_photo_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('빈 소개 사진 URL만 있으면 목록을 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClubIntroPhotoStrip(imageUrls: ['', '  ']),
        ),
      ),
    );

    expect(find.byType(ListView), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('유효한 소개 사진 URL만 가로 목록에 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClubIntroPhotoStrip(
            imageUrls: ['', 'https://example.com/club.jpg', '  '],
          ),
        ),
      ),
    );

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.scrollDirection, Axis.horizontal);
    expect(find.byType(Image), findsOneWidget);
  });
}
