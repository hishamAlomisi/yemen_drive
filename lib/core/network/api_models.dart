class ApiProblemDetails {
  const ApiProblemDetails({
    required this.title,
    required this.status,
    this.detail,
    this.code,
    this.errors = const <String, List<String>>{},
  });

  factory ApiProblemDetails.fromJson(
    Map<String, Object?> json, {
    int? fallbackStatus,
  }) {
    final rawErrors = json['errors'];
    final errors = <String, List<String>>{};
    if (rawErrors is Map) {
      for (final entry in rawErrors.entries) {
        final value = entry.value;
        errors[entry.key.toString()] = value is List
            ? value.map((item) => item.toString()).toList()
            : <String>[value.toString()];
      }
    }
    final message = json['message']?.toString();
    return ApiProblemDetails(
      title: json['title']?.toString() ??
          message ??
          'تعذر إكمال الطلب',
      status: int.tryParse(json['status']?.toString() ?? '') ??
          fallbackStatus ??
          0,
      detail: json['detail']?.toString() ?? message,
      code: json['code']?.toString(),
      errors: errors,
    );
  }

  final String title;
  final int status;
  final String? detail;
  final String? code;
  final Map<String, List<String>> errors;
}

sealed class ApiResult<T> {
  const ApiResult();
}

class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.data);
  final T data;
}

class ApiFailure<T> extends ApiResult<T> {
  const ApiFailure(this.problem);
  final ApiProblemDetails problem;
}

class PagedResponse<T> {
  const PagedResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int totalCount;
}
