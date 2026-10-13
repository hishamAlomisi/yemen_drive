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
          icon: Icon(
            showServices ? Icons.apps_outlined : Icons.favorite_border_rounded,
          ),
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
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Material(
          color: Colors.white,
          elevation: 10,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              indicatorColor: const Color(0xFF102C50),
              indicatorShape: const StadiumBorder(),
              iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected)
                      ? Colors.white
                      : const Color(0xFF607B95),
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
                (states) => TextStyle(
                  color: states.contains(WidgetState.selected)
                      ? const Color(0xFF102C50)
                      : const Color(0xFF607B95),
                  fontSize: 10,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: onTap,
              destinations: destinations,
              backgroundColor: Colors.transparent,
              elevation: 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              height: 72,
            ),
          ),
        ),
      );
}
