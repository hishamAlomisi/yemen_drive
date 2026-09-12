import 'package:get/get.dart';
import '../../bindings/account_binding.dart';

class HistoryBinding extends Bindings {
  @override
  void dependencies() => AccountBinding().dependencies();
}
