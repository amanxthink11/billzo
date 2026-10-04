import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/catalog/unit_of_measurement.dart';
import 'package:billzo/presentation/providers/catalog_providers.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Modal dialog to view and create Units of Measurement.
class UnitManagerDialog extends ConsumerStatefulWidget {
  final String businessId;

  const UnitManagerDialog({super.key, required this.businessId});

  @override
  ConsumerState<UnitManagerDialog> createState() => _UnitManagerDialogState();
}

class _UnitManagerDialogState extends ConsumerState<UnitManagerDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _shortNameController = TextEditingController();
  bool _allowDecimal = false;
  final int _decimalPlaces = 2;
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    super.dispose();
  }

  Future<void> _addUnit() async {
    final name = _nameController.text.trim();
    final shortName = _shortNameController.text.trim().toUpperCase();
    if (name.isEmpty || shortName.isEmpty) return;

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final service = ref.read(catalogServiceProvider);
      await service.createUnit(
        UnitOfMeasurement(
          id: '',
          businessId: widget.businessId,
          name: name,
          shortName: shortName,
          isDecimalAllowed: _allowDecimal,
          decimalPlaces: _allowDecimal ? _decimalPlaces : 0,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      _nameController.clear();
      _shortNameController.clear();
      ref.invalidate(unitsListProvider);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unitsAsync = ref.watch(unitsListProvider);

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.straighten_outlined, color: BillzoColors.primaryBlue, size: 24),
                  const SizedBox(width: 12),
                  const Text('Units of Measurement (UOM)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),

            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                child: Text(_error!, style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13)),
              ),

            // Add Unit Form
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Unit Name *',
                            hintText: 'e.g. Bags, Tons, Dozens',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _shortNameController,
                          decoration: const InputDecoration(
                            labelText: 'Code *',
                            hintText: 'e.g. BAG, TON',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isCreating ? null : _addUnit,
                        child: _isCreating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Add Unit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _allowDecimal,
                        onChanged: (val) {
                          setState(() {
                            _allowDecimal = val ?? false;
                          });
                        },
                      ),
                      const Text('Allow fractional quantities (e.g. 1.25)', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // List of Units
            Expanded(
              child: unitsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Error: $e')),
                data: (units) {
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    itemCount: units.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final u = units[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            u.shortName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BillzoColors.primaryBlue),
                          ),
                        ),
                        title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          u.isDecimalAllowed ? 'Fractional (up to ${u.decimalPlaces} decimals)' : 'Integer units only',
                          style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                        ),
                        trailing: u.isDefault
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: BillzoColors.successGreen.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Standard',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillzoColors.successGreen),
                                ),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
