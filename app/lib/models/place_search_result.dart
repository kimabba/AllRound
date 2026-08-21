class PlaceSearchResult {
  const PlaceSearchResult({
    required this.id,
    required this.name,
    required this.address,
    required this.roadAddress,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.phone,
  });

  final String id;
  final String name;
  final String address;
  final String roadAddress;
  final double latitude;
  final double longitude;
  final String category;
  final String phone;

  String get preferredAddress => roadAddress.isNotEmpty ? roadAddress : address;
  String get displayText => '$name · $preferredAddress';

  PlaceSearchResult withCoordinates({
    required double latitude,
    required double longitude,
  }) {
    return PlaceSearchResult(
      id: id,
      name: name,
      address: address,
      roadAddress: roadAddress,
      latitude: latitude,
      longitude: longitude,
      category: category,
      phone: phone,
    );
  }

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) {
    return PlaceSearchResult(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      roadAddress: json['roadAddress'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      category: json['category'] as String,
      phone: json['phone'] as String,
    );
  }
}
