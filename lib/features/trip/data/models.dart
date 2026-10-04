class Landmark {
  const Landmark(this.name, this.lat, this.lng);
  final String name;
  final double lat, lng;
  factory Landmark.fromJson(Map<String, dynamic> j) =>
      Landmark(j['name'], (j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

class Emergency {
  const Emergency(this.police, this.ambulance, this.general);
  final String police, ambulance, general;
  factory Emergency.fromJson(Map<String, dynamic> j) =>
      Emergency(j['police'], j['ambulance'], j['general']);
}

class Country {
  const Country({
    required this.id,
    required this.name,
    required this.flag,
    required this.currency,
    required this.utcOffset,
    required this.tzRule,
    required this.tzLabel,
    required this.emergency,
    required this.landmarks,
  });
  final String id, name, flag, currency, tzRule, tzLabel;
  final int utcOffset;
  final Emergency emergency;
  final List<Landmark> landmarks;

  factory Country.fromJson(Map<String, dynamic> j) => Country(
        id: j['id'],
        name: j['name'],
        flag: j['flag'],
        currency: j['currency'],
        utcOffset: j['utcOffset'],
        tzRule: j['tzRule'],
        tzLabel: j['tzLabel'],
        emergency: Emergency.fromJson(Map<String, dynamic>.from(j['emergency'])),
        landmarks: (j['landmarks'] as List)
            .map((e) => Landmark.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Trip {
  const Trip({
    required this.countryId,
    this.city = '',
    this.days = 3,
    this.budgetIdr = 0,
  });
  final String countryId, city;
  final int days;
  final double budgetIdr;

  Map<String, dynamic> toJson() =>
      {'countryId': countryId, 'city': city, 'days': days, 'budget': budgetIdr};
  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        countryId: j['countryId'],
        city: j['city'] ?? '',
        days: j['days'] ?? 3,
        budgetIdr: (j['budget'] as num?)?.toDouble() ?? 0,
      );
}
