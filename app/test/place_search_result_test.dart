import 'package:allround/models/place_search_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('도로명 주소를 우선해 활동 장소 표시 문구를 만든다', () {
    final place = PlaceSearchResult.fromJson({
      'id': '123',
      'name': '잠실 풋살장',
      'address': '서울 송파구 잠실동 1',
      'roadAddress': '서울 송파구 올림픽로 1',
      'latitude': 37.5,
      'longitude': 127.1,
      'category': '스포츠 > 풋살장',
      'phone': '',
    });

    expect(place.preferredAddress, '서울 송파구 올림픽로 1');
    expect(place.displayText, '잠실 풋살장 · 서울 송파구 올림픽로 1');
  });

  test('도로명 주소가 없으면 지번 주소를 사용한다', () {
    final place = PlaceSearchResult.fromJson({
      'id': '123',
      'name': '테니스장',
      'address': '서울 강남구 역삼동 1',
      'roadAddress': '',
      'latitude': 37.5,
      'longitude': 127.1,
      'category': '',
      'phone': '',
    });

    expect(place.preferredAddress, '서울 강남구 역삼동 1');
  });
}
