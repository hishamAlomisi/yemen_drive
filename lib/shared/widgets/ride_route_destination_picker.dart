import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/ride_route_change_snapshot.dart';
import 'app_google_map.dart';

/// An isolated selector: search/taps only edit this screen's draft destination.
class RideRouteDestinationPicker extends StatefulWidget {
  const RideRouteDestinationPicker({
    required this.initialTarget,
    required this.search,
    required this.reverseGeocode,
    super.key,
  });
  final LatLng initialTarget;
  final Future<List<RideRouteDestination>> Function(String query) search;
  final Future<RideRouteDestination?> Function(LatLng point) reverseGeocode;

  @override
  State<RideRouteDestinationPicker> createState() =>
      _RideRouteDestinationPickerState();
}

class _RideRouteDestinationPickerState
    extends State<RideRouteDestinationPicker> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _label = TextEditingController();
  Timer? _debounce;
  int _searchGeneration = 0;
  int _pointGeneration = 0;
  List<RideRouteDestination> _results = const [];
  LatLng? _point;
  bool _searching = false;
  bool _resolving = false;
  String? _error;

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _results = const [];
      _searching = value.trim().length >= 2;
      _error = null;
    });
    if (!_searching) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await widget.search(value.trim());
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _results = results.where((v) => v.isValid).toList(growable: false);
          if (_results.isEmpty) {
            _error = 'لا توجد نتائج. جرّب اسمًا آخر أو حدد الموقع على الخريطة.';
          }
        });
      } catch (_) {
        if (mounted && generation == _searchGeneration) {
          setState(
            () =>
                _error = 'تعذر البحث عن المكان. تحقق من الاتصال وأعد المحاولة.',
          );
        }
      } finally {
        if (mounted && generation == _searchGeneration) {
          setState(() => _searching = false);
        }
      }
    });
  }

  void _selectResult(RideRouteDestination result) {
    ++_pointGeneration;
    ++_searchGeneration;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _point = LatLng(result.latitude, result.longitude);
      _label.text = result.label;
      _results = const [];
      _searching = false;
      _resolving = false;
      _error = null;
    });
  }

  Future<void> _selectMapPoint(LatLng point) async {
    final generation = ++_pointGeneration;
    ++_searchGeneration;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _point = point;
      _label.clear();
      _results = const [];
      _searching = false;
      _resolving = true;
      _error = null;
    });
    try {
      final result = await widget.reverseGeocode(point);
      if (!mounted || generation != _pointGeneration) return;
      setState(() {
        // Preserve the exact selected point; geocoding supplies only its label.
        if (result != null && result.label.trim().isNotEmpty) {
          _label.text = result.label;
        } else {
          _error = 'أضف اسمًا واضحًا للمكان المحدد على الخريطة.';
        }
      });
    } catch (_) {
      if (mounted && generation == _pointGeneration) {
        setState(
          () => _error = 'تعذر جلب اسم الموقع. أضف اسمًا واضحًا للمكان المحدد.',
        );
      }
    } finally {
      if (mounted && generation == _pointGeneration) {
        setState(() => _resolving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('اختيار الوجهة الجديدة')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _query,
                  onChanged: _scheduleSearch,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'ابحث عن مكان أو عنوان',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              if (_searching || _resolving) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(_error!),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AppGoogleMap(
                        initialTarget: widget.initialTarget,
                        focusTarget: _point,
                        onTap: _selectMapPoint,
                        markers: {
                          if (_point != null)
                            Marker(
                              markerId: const MarkerId('proposed_destination'),
                              position: _point!,
                            ),
                        },
                      ),
                    ),
                    if (_results.isNotEmpty)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Material(
                            elevation: 4,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 250),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _results.length,
                                itemBuilder: (context, index) => ListTile(
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(_results[index].label),
                                  onTap: () => _selectResult(_results[index]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'اختر نتيجة بحث أو اضغط على الخريطة لتحديد الوجهة.',
                    ),
                    TextField(
                      controller: _label,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'اسم الوجهة',
                        prefixIcon: Icon(Icons.place),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _point == null ||
                              _label.text.trim().isEmpty ||
                              _resolving
                          ? null
                          : () {
                              Navigator.pop(
                                context,
                                RideRouteDestination(
                                  latitude: _point!.latitude,
                                  longitude: _point!.longitude,
                                  label: _label.text.trim(),
                                ),
                              );
                            },
                      child: const Text('عرض فاتورة هذه الوجهة'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    ++_searchGeneration;
    ++_pointGeneration;
    _debounce?.cancel();
    _query.dispose();
    _label.dispose();
    super.dispose();
  }
}
