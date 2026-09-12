enum OnboardingArtwork { cityRide, fastPickup, liveTracking }

class OnboardingSlide {
  const OnboardingSlide({
    required this.titleKey,
    required this.subtitleKey,
    required this.artwork,
  });

  final String titleKey;
  final String subtitleKey;
  final OnboardingArtwork artwork;
}

class AuthSession {
  const AuthSession(
      {required this.accessToken, required this.refreshToken, this.userId});

  final String accessToken;
  final String refreshToken;
  final int? userId;
}

class SignInResult {
  const SignInResult.authenticated(this.session)
      : requiresOtp = false,
        challengeId = null;

  const SignInResult.requiresOtp(this.challengeId)
      : requiresOtp = true,
        session = null;

  final bool requiresOtp;
  final String? challengeId;
  final AuthSession? session;
}

class PhoneCountry {
  const PhoneCountry({
    required this.countryCode,
    required this.phoneCode,
    required this.flagEmoji,
    required this.name,
  });

  static const PhoneCountry yemen = PhoneCountry(
    countryCode: 'YE',
    phoneCode: '967',
    flagEmoji: '🇾🇪',
    name: 'اليمن',
  );

  final String countryCode;
  final String phoneCode;
  final String flagEmoji;
  final String name;
}
