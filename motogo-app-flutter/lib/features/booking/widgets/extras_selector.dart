import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../booking_models.dart';

/// Accessories/extras selector — mirrors Step 7 from templates-booking-form2.js.
/// Free base gear card + paid extras checkboxes with optional size picker.
class ExtrasSelector extends StatefulWidget {
  final List<ExtraCatalogItem> catalog;
  final List<SelectedExtra> selected;
  final ValueChanged<List<SelectedExtra>> onChanged;

  const ExtrasSelector({
    super.key,
    required this.catalog,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<ExtrasSelector> createState() => _ExtrasSelectorState();
}

class _ExtrasSelectorState extends State<ExtrasSelector> {
  late List<SelectedExtra> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selected);
  }

  bool _isSelected(String id) => _selected.any((e) => e.id == id);

  void _toggle(ExtraCatalogItem item) {
    setState(() {
      if (_isSelected(item.id)) {
        _selected.removeWhere((e) => e.id == item.id);
      } else {
        _selected.add(SelectedExtra(
          id: item.id,
          name: item.name,
          price: item.price,
        ));
      }
    });
    widget.onChanged(_selected);
  }

  void _setSize(String itemId, String size) {
    final idx = _selected.indexWhere((e) => e.id == itemId);
    if (idx >= 0) {
      setState(() => _selected[idx].size = size);
      widget.onChanged(_selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Free base gear card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
            border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Text('🛡️', style: TextStyle(fontSize: 24)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Základní výbava zdarma',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker),
                    ),
                    Text(
                      'Helma, rukavice, bunda, kalhoty',
                      style: TextStyle(fontSize: 11, color: MotoGoColors.g600),
                    ),
                  ],
                ),
              ),
              Text('✓', style: TextStyle(fontSize: 18, color: MotoGoColors.green)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Paid extras
        ...widget.catalog.map((item) {
          final selected = _isSelected(item.id);
          final selectedExtra = _selected.where((e) => e.id == item.id).firstOrNull;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => _toggle(item),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(
                    color: selected ? MotoGoColors.green : MotoGoColors.g200,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(item.icon ?? '🎒', style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                              if (item.description != null)
                                Text(item.description!, style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                            ],
                          ),
                        ),
                        Text('+${item.price.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
                        const SizedBox(width: 8),
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: selected ? MotoGoColors.green : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g200, width: 2),
                          ),
                          child: selected
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : null,
                        ),
                      ],
                    ),
                    // Size picker
                    if (selected && item.needsSize && item.sizes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: item.sizes.map((size) {
                            final isActive = selectedExtra?.size == size;
                            return GestureDetector(
                              onTap: () => _setSize(item.id, size),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isActive ? MotoGoColors.green : MotoGoColors.g100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isActive ? MotoGoColors.green : MotoGoColors.g200),
                                ),
                                child: Text(
                                  size,
                                  style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: isActive ? Colors.white : MotoGoColors.black,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
