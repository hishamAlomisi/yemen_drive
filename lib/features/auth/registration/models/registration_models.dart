class SignUpDraft {
  const SignUpDraft({required this.phone});

  final String phone;

  Map<String, Object?> toJson() => <String, Object?>{'phoneNumber': phone};
}

class ProfileDraft {
  const ProfileDraft({
    required this.fullName,
    required this.phone,
    required this.gender,
    required this.street,
    required this.city,
    required this.district,
  });

  final String fullName;
  final String phone;
  final String gender;
  final String street;
  final String city;
  final String district;
}
