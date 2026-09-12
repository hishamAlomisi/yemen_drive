import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

class ProfileData {
  const ProfileData(
      {this.id,
      this.name,
      this.phone,
      this.email,
      this.gender,
      this.street,
      this.city,
      this.district});
  final int? id;
  final String? name;
  final String? phone;
  final String? email;
  final String? gender;
  final String? street;
  final String? city;
  final String? district;
}

abstract interface class ProfileRepository {
  Future<ProfileData> get();
  Future<ProfileData> update(
      {String? name, String? phone, String? gender, String? street});
}

class ApiProfileRepository implements ProfileRepository {
  const ApiProfileRepository(this._client);
  final ApiClient _client;
  @override
  Future<ProfileData> get() async {
    final result = await _client
        .execute<Object?>(model: 'UserModel', operation: 'get', data: const {});
    if (result is! ApiSuccess) throw StateError('تعذر تحميل الملف الشخصي.');
    return _parse(result.data);
  }

  @override
  Future<ProfileData> update(
      {String? name, String? phone, String? gender, String? street}) async {
    final result = await _client.execute<Object?>(
        model: 'UserModel',
        operation: 'update',
        data: <String, Object?>{
          'displayName': name,
          'phoneNumber': phone,
          'gender': gender,
          'street': street,
        });
    if (result is! ApiSuccess) throw StateError('تعذر حفظ الملف الشخصي.');
    return _parse(result.data);
  }

  ProfileData _parse(Object? value) {
    final map =
        value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
    return ProfileData(
        id: int.tryParse('${map['id'] ?? ''}'),
        name: map['displayName']?.toString(),
        phone: map['phoneNumber']?.toString(),
        email: map['email']?.toString(),
        gender: map['gender']?.toString(),
        street: map['street']?.toString(),
        city: map['city']?.toString(),
        district: map['district']?.toString());
  }
}
