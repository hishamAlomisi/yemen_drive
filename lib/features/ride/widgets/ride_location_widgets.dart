import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../location_selection/repositories/location_search_repository.dart';
import '../models/ride_models.dart';

class RouteFieldsCard extends GetView<LocationController> {
  const RouteFieldsCard({
    this.allowEditing = false,
    this.fromFocusNode,
    this.toFocusNode,
    this.onFromSubmitted,
    this.onToSubmitted,
    this.onFromChanged,
    this.onToChanged,
    this.onFromTap,
    this.onToTap,
    this.onClearFrom,
    this.onClearTo,
    this.compact = false,
    this.cardColor,
    this.cardBorderColor,
    super.key,
  });

  final bool allowEditing;
  final FocusNode? fromFocusNode;
  final FocusNode? toFocusNode;
  final ValueChanged<String>? onFromSubmitted;
  final ValueChanged<String>? onToSubmitted;
  final ValueChanged<String>? onFromChanged;
  final ValueChanged<String>? onToChanged;
  final VoidCallback? onFromTap;
  final VoidCallback? onToTap;
  final VoidCallback? onClearFrom;
  final VoidCallback? onClearTo;
  final bool compact;
  final Color? cardColor;
  final Color? cardBorderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = AppCard(
      color: cardColor,
      borderColor: cardBorderColor,
      padding: EdgeInsets.all(compact ? 6 : AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: compact ? 10 : 15),
            child: _RouteIndicator(compact: compact),
          ),
          SizedBox(width: compact ? 6 : AppSpacing.sm),
          Expanded(
            child: Column(
              children: <Widget>[
                AppTextField(
                  controller: controller.fromController,
                  hint: 'نقطة الانطلاق',
                  readOnly: !allowEditing,
                  focusNode: fromFocusNode,
                  textInputAction: TextInputAction.next,
                  onChanged: onFromChanged,
                  onSubmitted: onFromSubmitted,
                  onTap: onFromTap ??
                      (allowEditing
                          ? null
                          : () => controller.startSearch(field: 0)),
                  prefixIcon: Icon(Icons.my_location_rounded, size: 19),
                  // In the Arabic (RTL) interface the suffix is rendered on
                  // the left, which keeps the map-point icon on the right.
                  suffixIcon: _ClearLocationFieldButton(
                    textController: controller.fromController,
                    onPressed: onClearFrom,
                  ),
                ),
                SizedBox(height: compact ? 6 : AppSpacing.sm),
                AppTextField(
                  controller: controller.toController,
                  hint: 'إلى أين؟',
                  readOnly: !allowEditing,
                  focusNode: toFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: onToChanged,
                  onSubmitted: onToSubmitted,
                  onTap: onToTap ??
                      (allowEditing
                          ? null
                          : () => controller.startSearch(field: 1)),
                  prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                  suffixIcon: _ClearLocationFieldButton(
                    textController: controller.toController,
                    onPressed: onClearTo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!compact) return content;
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          isDense: true,
        ),
      ),
      child: content,
    );
  }
}

class _ClearLocationFieldButton extends StatelessWidget {
  const _ClearLocationFieldButton({
    required this.textController,
    required this.onPressed,
  });

  final TextEditingController textController;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox.shrink();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: textController,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        return IconButton(
          tooltip: 'مسح والبحث من جديد',
          icon: const Icon(Icons.close_rounded, size: 19),
          onPressed: onPressed,
        );
      },
    );
  }
}

class InteractiveRouteFieldsOverlay extends StatefulWidget {
  const InteractiveRouteFieldsOverlay({super.key});

  @override
  State<InteractiveRouteFieldsOverlay> createState() =>
      _InteractiveRouteFieldsOverlayState();
}

class _InteractiveRouteFieldsOverlayState
    extends State<InteractiveRouteFieldsOverlay> {
  final LocationController _controller = Get.find<LocationController>();
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  final LayerLink _fieldsLink = LayerLink();
  final GlobalKey _fieldsKey = GlobalKey();
  Timer? _debounce;
  OverlayEntry? _suggestionsOverlay;
  String _query = '';

  bool get _hasActiveFocus => _fromFocus.hasFocus || _toFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    _fromFocus.addListener(_refreshFocusState);
    _toFocus.addListener(_refreshFocusState);
  }

  void _refreshFocusState() {
    if (!_hasActiveFocus) {
      _debounce?.cancel();
      _query = '';
      _controller.cancelSearch();
      _hideSuggestions();
    } else {
      _showSuggestions();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideSuggestions();
    _fromFocus.removeListener(_refreshFocusState);
    _toFocus.removeListener(_refreshFocusState);
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _activate(int field) {
    _controller.activeField.value = field;
    _controller.searchResults.clear();
    _query = '';
    _showSuggestions();
    setState(() {});
  }

  void _clearAndFocus(int field) {
    _debounce?.cancel();
    _query = '';
    _controller.clearRouteField(field);
    final focus = field == 0 ? _fromFocus : _toFocus;
    FocusScope.of(context).requestFocus(focus);
    _showSuggestions();
    _suggestionsOverlay?.markNeedsBuild();
    setState(() {});
  }

  void _search(int field, String value) {
    _controller.activeField.value = field;
    _query = value.trim();
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _controller.searchPlaces(value),
    );
    _suggestionsOverlay?.markNeedsBuild();
    setState(() {});
  }

  Future<void> _select(LocationSearchResult result) async {
    _debounce?.cancel();
    _query = '';
    _hideSuggestions();
    _fromFocus.unfocus();
    _toFocus.unfocus();
    await _controller.selectSearchResult(result, closeSearchPage: false);
    if (mounted) setState(() {});
  }

  Future<void> _selectRecent(RecentPlace place) async {
    _debounce?.cancel();
    _query = '';
    _hideSuggestions();
    _fromFocus.unfocus();
    _toFocus.unfocus();
    await _controller.selectPlace(place);
    if (mounted) setState(() {});
  }

  void _showSuggestions() {
    if (_suggestionsOverlay != null || !mounted) {
      _suggestionsOverlay?.markNeedsBuild();
      return;
    }
    _suggestionsOverlay = OverlayEntry(builder: _buildSuggestionsOverlay);
    Overlay.of(context).insert(_suggestionsOverlay!);
  }

  void _hideSuggestions() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay?.dispose();
    _suggestionsOverlay = null;
  }

  void _dismissSuggestions() {
    _fromFocus.unfocus();
    _toFocus.unfocus();
    _hideSuggestions();
  }

  void _handleOverlayTap(TapDownDetails details) {
    final renderBox =
        _fieldsKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final fieldsRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
      if (fieldsRect.contains(details.globalPosition)) {
        final localY = details.globalPosition.dy - fieldsRect.top;
        final field = localY < fieldsRect.height / 2 ? 0 : 1;
        _controller.activeField.value = field;
        FocusScope.of(context).requestFocus(field == 0 ? _fromFocus : _toFocus);
        _suggestionsOverlay?.markNeedsBuild();
        return;
      }
    }
    _dismissSuggestions();
  }

  Widget _buildSuggestionsOverlay(BuildContext context) {
    final renderBox =
        _fieldsKey.currentContext?.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 320.0;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: _handleOverlayTap,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _fieldsLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 7),
          child: SizedBox(
            width: width,
            child: Obx(() {
              final isSearching = _controller.isSearching.value;
              final searchFailed = _controller.searchFailed.value;
              final results = _controller.searchResults.toList();
              final savedPlaces = _controller.filteredSavedPlaces(_query);
              final hasQuery = _query.length >= 2;
              final showEmpty = hasQuery &&
                  results.isEmpty &&
                  savedPlaces.isEmpty &&
                  !isSearching &&
                  !searchFailed;
              return Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 18,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 310),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    shrinkWrap: true,
                    children: <Widget>[
                      ...savedPlaces.map(
                        (place) => RecentPlaceTile(
                          place: place,
                          onTap: () => _selectRecent(place),
                        ),
                      ),
                      if (savedPlaces.isNotEmpty &&
                          (results.isNotEmpty || isSearching))
                        const Divider(height: 1),
                      if (isSearching)
                        const Padding(
                          padding: EdgeInsets.all(14),
                          child: LinearProgressIndicator(),
                        ),
                      ...results.map(
                        (result) => ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1,
                          ),
                          minLeadingWidth: 28,
                          leading: const Icon(
                            Icons.location_on_outlined,
                            size: 19,
                          ),
                          title: Text(
                            result.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            result.formattedAddress,
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _select(result),
                        ),
                      ),
                      if (showEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.search_off_rounded),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'لا توجد أماكن مطابقة لـ "$_query"',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
        key: _fieldsKey,
        link: _fieldsLink,
        child: RouteFieldsCard(
          allowEditing: true,
          compact: true,
          cardColor: const Color(0xD92D355E),
          cardBorderColor: const Color(0x667E89B8),
          fromFocusNode: _fromFocus,
          toFocusNode: _toFocus,
          onFromTap: () => _activate(0),
          onToTap: () => _activate(1),
          onClearFrom: () => _clearAndFocus(0),
          onClearTo: () => _clearAndFocus(1),
          onFromChanged: (value) => _search(0, value),
          onToChanged: (value) => _search(1, value),
        ),
      );
}

class RecentPlacesList extends GetView<LocationController> {
  const RecentPlacesList({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: controller.recentPlaces
            .map(
              (place) => RecentPlaceTile(
                place: place,
                onTap: () => controller.selectPlace(place),
              ),
            )
            .toList(growable: false),
      );
}

class RecentPlaceTile extends StatelessWidget {
  const RecentPlaceTile({required this.place, required this.onTap, super.key});

  final RecentPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (place.kind) {
      'home' => Icons.home_outlined,
      'work' => Icons.work_outline_rounded,
      _ => Icons.history_rounded,
    };
    return ListTile(
      dense: true,
      minVerticalPadding: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      onTap: onTap,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        place.title,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        place.address,
        style: Theme.of(context).textTheme.labelSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.history_rounded, size: 18),
    );
  }
}

class LocationSearchForm extends StatefulWidget {
  const LocationSearchForm({super.key});

  @override
  State<LocationSearchForm> createState() => _LocationSearchFormState();
}

class LocationPickerSearchOverlay extends StatefulWidget {
  const LocationPickerSearchOverlay({super.key});

  @override
  State<LocationPickerSearchOverlay> createState() =>
      _LocationPickerSearchOverlayState();
}

class _LocationPickerSearchOverlayState
    extends State<LocationPickerSearchOverlay> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _controller = Get.find<LocationController>();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hint: 'ابحث عن مكان أو شارع',
            prefixIcon: Icon(Icons.search_rounded),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      _query = '';
                      _debounce?.cancel();
                      _controller.searchPlaces('');
                      setState(() {});
                    },
                  ),
            onChanged: (value) {
              _query = value.trim();
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 400),
                () => _controller.searchPlaces(value),
              );
              setState(() {});
            },
          ),
          Obx(() {
            if (_controller.isSearching.value) {
              return Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              );
            }
            if (_controller.searchFailed.value) {
              return const SizedBox.shrink();
            }
            final savedPlaces = _controller.filteredSavedPlaces(_query);
            if (_controller.searchResults.isEmpty &&
                savedPlaces.isEmpty &&
                _query.length >= 2) {
              return AppCard(
                child: Row(
                  children: <Widget>[
                    Icon(Icons.search_off_rounded),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text('لا توجد أماكن مطابقة لـ "$_query"')),
                  ],
                ),
              );
            }
            if (_controller.searchResults.isEmpty && savedPlaces.isEmpty) {
              return const SizedBox.shrink();
            }
            return AppCard(
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  shrinkWrap: true,
                  itemCount:
                      savedPlaces.length + _controller.searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    if (index < savedPlaces.length) {
                      final place = savedPlaces[index];
                      return RecentPlaceTile(
                        place: place,
                        onTap: () async {
                          _debounce?.cancel();
                          _searchController.clear();
                          _query = '';
                          _searchFocusNode.unfocus();
                          setState(() {});
                          await _controller.selectPlace(place);
                        },
                      );
                    }
                    final result =
                        _controller.searchResults[index - savedPlaces.length];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      minLeadingWidth: 28,
                      leading: const Icon(
                        Icons.location_on_outlined,
                        size: 19,
                      ),
                      title: Text(
                        result.title,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        result.formattedAddress,
                        style: Theme.of(context).textTheme.labelSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        _debounce?.cancel();
                        _searchController.clear();
                        _query = '';
                        _searchFocusNode.unfocus();
                        setState(() {});
                        await _controller.selectSearchResult(
                          result,
                          closeSearchPage: false,
                        );
                      },
                    );
                  },
                ),
              ),
            );
          }),
        ],
      );
}

class _LocationSearchFormState extends State<LocationSearchForm> {
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();
  late final LocationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<LocationController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target =
          _controller.activeField.value == 0 ? _pickupFocus : _destinationFocus;
      target.requestFocus();
    });
  }

  @override
  void dispose() {
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RouteFieldsCard(
            allowEditing: true,
            fromFocusNode: _pickupFocus,
            toFocusNode: _destinationFocus,
            onFromSubmitted: (_) {
              _controller.activeField.value = 1;
              _destinationFocus.requestFocus();
            },
            onToSubmitted: (_) => _controller.useTypedValue(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'الأماكن الحديثة',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const RecentPlacesList(),
        ],
      );
}

class _RouteIndicator extends StatelessWidget {
  const _RouteIndicator({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LocationController>();
    final inactiveColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: .16);
    return Obx(() {
      final isRouteReady = controller.canContinueLocationFlow;
      return SizedBox(
        width: 18,
        height: compact ? 62 : 76,
        child: Column(
          children: <Widget>[
            Icon(Icons.circle, size: 11, color: AppColors.primaryDark),
            Expanded(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  width: isRouteReady ? 3 : 2,
                  decoration: BoxDecoration(
                    color: isRouteReady
                        ? Theme.of(context).colorScheme.primary
                        : inactiveColor,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isRouteReady
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .72),
                              blurRadius: 7,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
            Icon(
              Icons.square_rounded,
              size: 12,
              color: AppColors.secondary,
            ),
          ],
        ),
      );
    });
  }
}
