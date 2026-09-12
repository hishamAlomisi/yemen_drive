import 'package:get/get.dart';
import '../../bindings/account_binding.dart';

class FavouritesBinding extends Bindings {
  @override
  void dependencies() => AccountBinding().dependencies();
}
