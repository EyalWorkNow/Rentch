class User {
  final String id;
  final String name;
  final int age;
  final String photoUrl;
  final String bio;
  final double distance;
  final List<String> interests;
  final bool likesYou;

  const User({
    required this.id,
    required this.name,
    required this.age,
    required this.photoUrl,
    required this.bio,
    required this.distance,
    required this.interests,
    this.likesYou = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      age: json['age'] as int,
      photoUrl: json['photoUrl'] as String,
      bio: json['bio'] as String,
      distance: (json['distance'] as num).toDouble(),
      interests: List<String>.from(json['interests'] as List<dynamic>),
      likesYou: json['likesYou'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'photoUrl': photoUrl,
      'bio': bio,
      'distance': distance,
      'interests': interests,
      'likesYou': likesYou,
    };
  }

  User copyWith({
    String? id,
    String? name,
    int? age,
    String? photoUrl,
    String? bio,
    double? distance,
    List<String>? interests,
    bool? likesYou,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      distance: distance ?? this.distance,
      interests: interests ?? this.interests,
      likesYou: likesYou ?? this.likesYou,
    );
  }
}
