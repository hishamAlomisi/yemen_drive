import 'package:flutter_test/flutter_test.dart';

import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';

class _OfferApi extends ApiClient {
  _OfferApi() : super(SecureStorageService());

  ApiProblemDetails? failure;
  final calls = <Map<String, Object?>>[];

  @override
  Future<ApiResult<T>> execute<T>({
    required String model,
    required String operation,
    Object? data,
    T Function(Object?)? parse,
  }) async {
    calls.add({
      'model': model,
      'operation': operation,
      'data': Map<String, Object?>.from(data! as Map),
    });
    if (failure != null) return ApiFailure<T>(failure!);
    return ApiSuccess<T>(null as T);
  }
}

void main() {
  for (final scenario in <(ApiProblemDetails, String)>[
    (
      ApiProblemDetails.fromJson({
        'success': false,
        'code': 'offer_expired',
        'message': 'انتهت صلاحية عرض السائق. انتظر عرضًا جديدًا.',
      }),
      'انتهت صلاحية عرض السائق. انتظر عرضًا جديدًا.',
    ),
    (
      const ApiProblemDetails(
        title: 'تعذر إكمال الطلب',
        status: 409,
        detail: 'يجب تقييم الرحلة السابقة قبل قبول عرض جديد.',
        code: 'rating_required',
      ),
      'يجب تقييم الرحلة السابقة قبل قبول عرض جديد.',
    ),
    (
      const ApiProblemDetails(
        title: 'بيانات غير صالحة',
        status: 400,
        errors: {
          'offerId': ['العرض لا يتبع طلب الرحلة الحالي.'],
        },
      ),
      'العرض لا يتبع طلب الرحلة الحالي.',
    ),
    (
      const ApiProblemDetails(title: 'تعذّر الاتصال بالخادم', status: 0),
      'تعذّر الاتصال بالخادم',
    ),
  ]) {
    test('offer acceptance preserves the server reason: ${scenario.$2}',
        () async {
      final api = _OfferApi()..failure = scenario.$1;
      final repository = ApiRideNegotiationRepository(api);

      await expectLater(
        repository.acceptOffer('43', '1839'),
        throwsA(
          isA<FormatException>()
              .having((error) => error.message, 'message', scenario.$2),
        ),
      );
    });
  }

  test('successive acceptances send each ride and offer identity without reuse',
      () async {
    final api = _OfferApi();
    final repository = ApiRideNegotiationRepository(api);
    await repository.acceptOffer('42', '1838');
    await repository.acceptOffer('43', '1839');

    expect(api.calls, [
      {
        'model': 'RideOfferActionModel',
        'operation': 'accept',
        'data': {'rideId': '42', 'offerId': '1838'},
      },
      {
        'model': 'RideOfferActionModel',
        'operation': 'accept',
        'data': {'rideId': '43', 'offerId': '1839'},
      },
    ]);
  });
}
