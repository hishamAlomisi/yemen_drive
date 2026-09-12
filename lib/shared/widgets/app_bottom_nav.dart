import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.currentIndex,
    required this.onTap,
    this.showServices = false,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool showServices;

  List<NavigationDestination> get destinations => <NavigationDestination>[
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'الرئيسية',
        ),
        NavigationDestination(
          icon: Icon(showServices
              ? Icons.apps_outlined
              : Icons.favorite_border_rounded,),
          selectedIcon:
              Icon(showServices ? Icons.apps_rounded : Icons.favorite_rounded),
          label: showServices ? 'الخدمات' : 'المفضلة',
        ),
        const NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet_rounded),
          label: 'المحفظة',
        ),
        const NavigationDestination(
          icon: Icon(Icons.local_offer_outlined),
          selectedIcon: Icon(Icons.local_offer_rounded),
          label: 'العروض',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'حسابي',
        ),
      ];

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        destinations: destinations,
        indicatorColor: Theme.of(context).colorScheme.primary,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 72,
      );
}
