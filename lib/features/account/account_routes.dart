import 'package:get/get.dart';

import 'bindings/account_binding.dart';
import 'change_password/bindings/change_password_binding.dart';
import 'change_password/views/change_password_view.dart';
import 'contact/bindings/contact_binding.dart';
import 'contact/views/contact_view.dart';
import 'delete_account/bindings/delete_account_binding.dart';
import 'delete_account/views/delete_account_view.dart';
import 'favourites/bindings/favourites_binding.dart';
import 'favourites/views/favourites_view.dart';
import 'history/views/history_view.dart';
import 'language/bindings/language_binding.dart';
import 'language/views/language_view.dart';
import 'models/account_models.dart';
import 'offers/views/offers_view.dart';
import 'profile/bindings/profile_binding.dart';
import 'profile/views/profile_view.dart';
import 'settings/views/settings_view.dart'
    show HelpPage, PrivacyPage, SettingsPage;
import 'support/views/support_view.dart';
import 'wallet/bindings/wallet_binding.dart';
import 'wallet/views/wallet_view.dart';

abstract final class AccountRoutes {
  static const String favourites = '/account/favourites';
  static const String wallet = '/account/wallet';
  static const String addAmount = '/account/wallet/add-amount';
  static const String bank = '/account/wallet/bank';
  static const String walletSuccess = '/account/wallet/success';
  static const String offers = '/account/offers';
  static const String offerDetails = '/account/offers/details';
  static const String profile = '/account/profile';
  static const String menu = '/account/menu';
  static const String historyUpcoming = '/account/history/upcoming';
  static const String historyCompleted = '/account/history/completed';
  static const String historyCancelled = '/account/history/cancelled';
  static const String complaint = '/account/complaint';
  static const String complaintSuccess = '/account/complaint/success';
  static const String referral = '/account/referral';
  static const String about = '/account/about';
  static const String settings = '/account/settings';
  static const String changePassword = '/account/settings/password';
  static const String language = '/account/settings/language';
  static const String privacy = '/account/settings/privacy';
  static const String contact = '/account/settings/contact';
  static const String deleteAccount = '/account/settings/delete';
  static const String help = '/account/help';
}

List<GetPage<dynamic>> get accountPages => <GetPage<dynamic>>[
      GetPage<dynamic>(
        name: AccountRoutes.favourites,
        page: FavouritesPage.new,
        binding: FavouritesBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.wallet,
        page: WalletPage.new,
        binding: WalletBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.addAmount,
        page: AddAmountPage.new,
        binding: WalletBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.bank,
        page: BankAccountPage.new,
        binding: WalletBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.walletSuccess,
        page: WalletSuccessPage.new,
        binding: WalletBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.offers,
        page: OffersPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.offerDetails,
        page: OfferDetailsPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.profile,
        page: ProfilePage.new,
        binding: ProfileBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.menu,
        page: SideMenuPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.historyUpcoming,
        page: () => const HistoryPage(status: RideHistoryStatus.upcoming),
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.historyCompleted,
        page: () => const HistoryPage(status: RideHistoryStatus.completed),
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.historyCancelled,
        page: () => const HistoryPage(status: RideHistoryStatus.cancelled),
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.complaint,
        page: ComplaintPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.complaintSuccess,
        page: ComplaintSuccessPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.referral,
        page: ReferralPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.about,
        page: AboutPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.settings,
        page: SettingsPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.changePassword,
        page: ChangePasswordPage.new,
        binding: ChangePasswordBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.language,
        page: LanguagePage.new,
        binding: LanguageBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.privacy,
        page: PrivacyPage.new,
        binding: AccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.contact,
        page: ContactPage.new,
        binding: ContactBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.deleteAccount,
        page: DeleteAccountPage.new,
        binding: DeleteAccountBinding(),
      ),
      GetPage<dynamic>(
        name: AccountRoutes.help,
        page: HelpPage.new,
        binding: AccountBinding(),
      ),
    ];
