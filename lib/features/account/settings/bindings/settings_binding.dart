import 'package:get/get.dart';
import '../../bindings/account_binding.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() => AccountBinding().dependencies();
}
