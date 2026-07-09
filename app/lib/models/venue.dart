class Venue {
  const Venue({
    required this.id,
    required this.sport,
    required this.name,
    required this.region,
    this.regionCode,
    this.address,
    required this.venueType,
    this.courtCount,
    this.phone,
    this.website,
  });

  final String id;
  final String sport;
  final String name;
  final String region;
  final String? regionCode;
  final String? address;
  final String venueType;
  final int? courtCount;
  final String? phone;
  final String? website;

  factory Venue.fromJson(Map<String, dynamic> j) {
    final courtCount = j['court_count'];
    return Venue(
      id: j['id'] as String,
      sport: j['sport'] as String,
      name: j['name'] as String,
      region: j['region'] as String,
      regionCode: j['region_code'] as String?,
      address: j['address'] as String?,
      venueType: (j['venue_type'] as String?) ?? 'unknown',
      courtCount: courtCount is int ? courtCount : null,
      phone: j['phone'] as String?,
      website: j['website'] as String?,
    );
  }
}
