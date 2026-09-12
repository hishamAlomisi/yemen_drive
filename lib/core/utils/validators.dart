abstract final class AppValidators {
  static final RegExp _emailPattern = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$",
  );
  static final RegExp _phonePattern = RegExp(r'^\+?[0-9]{8,15}$');
  static final RegExp _passwordNumber = RegExp(r'[0-9]');
  static final RegExp _passwordSymbol = RegExp(r'[^A-Za-z0-9\s]');

  static String? required(String? value) {
    if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب.';
    return null;
  }

  static String? email(String? value) {
    final requiredError = required(value);
    if (requiredError != null) return requiredError;
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'أدخل بريدًا إلكترونيًا صحيحًا.';
    }
    return null;
  }

  static String? phone(String? value) {
    final requiredError = required(value);
    if (requiredError != null) return requiredError;
    final normalized = value!.replaceAll(RegExp(r'[\s()-]'), '');
    if (!_phonePattern.hasMatch(normalized)) return 'أدخل رقم جوال صحيحًا.';
    return null;
  }

  static String? emailOrPhone(String? value) {
    final requiredError = required(value);
    if (requiredError != null) return requiredError;
    final input = value!.trim();
    final normalizedPhone = input.replaceAll(RegExp(r'[\s()-]'), '');
    if (!_emailPattern.hasMatch(input) &&
        !_phonePattern.hasMatch(normalizedPhone)) {
      return 'أدخل بريدًا إلكترونيًا أو رقم جوال صحيحًا.';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredError = required(value);
    if (requiredError != null) return requiredError;
    if (value!.length < 8 ||
        !_passwordNumber.hasMatch(value) ||
        !_passwordSymbol.hasMatch(value)) {
      return 'استخدم 8 أحرف على الأقل مع رقم وحرف خاص.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final passwordError = AppValidators.password(value);
    if (passwordError != null) return passwordError;
    if (value != password) return 'كلمتا المرور غير متطابقتين.';
    return null;
  }

  static String? otp(String? value) {
    if (value == null || !RegExp(r'^\d{6}$').hasMatch(value)) {
      return 'أدخل رمز التحقق كاملًا.';
    }
    return null;
  }
}
