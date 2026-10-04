import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/application/recurring/recurring_invoice_service.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/recurring_providers.dart';

/// Modal dialog presented when offline catch-up detects missed recurring cycles.
class MissedSchedulesDialog extends ConsumerStatefulWidget {
  final String businessId;
  final List<MissedScheduleRecord> missedRecords;

  const MissedSchedulesDialog({
    super.key,
    required this.businessId,
    required this.missedRecords,
  });

  @override
  ConsumerState<MissedSchedulesDialog> createState() => _MissedSchedulesDialogState();
}

class _MissedSchedulesDialogState extends ConsumerState<MissedSchedulesDialog> {
  late final Map<String, MissedResolutionAction> _selectedActions;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedActions = {
      for (final record in widget.missedRecords)
        record.profile.id: MissedResolutionAction.generateAll,
    };
  }

  void _setAllActions(MissedResolutionAction action) {
    setState(() {
      for (final record in widget.missedRecords) {
        _selectedActions[record.profile.id] = action;
      }
    });
  }

  Future<void> _processCatchUp() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(recurringInvoiceServiceProvider);
      final resolutions = _selectedActions.entries
          .map((e) => MissedScheduleResolution(profileId: e.key, action: e.value))
          .toList();

      await service.processMissedSchedules(
        widget.businessId,
        resolutions,
      );

      // Invalidate relevant providers to refresh UI
      ref.invalidate(recurringInvoicesProvider(widget.businessId));
      ref.invalidate(missedSchedulesProvider(widget.businessId));

      if (mounted) {
        Navigator.of(context).pop(resolutions.length);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Failed to process missed schedules: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.history_toggle_off, color: BillzoColors.warningOrange, size: 28),
          SizedBox(width: 10),
          Text(
            'Missed Recurring Invoices Detected',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: BillzoColors.warningOrange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The device was offline or closed during scheduled invoice runs. '
                        'Review the missed cycles below and select how Billzo should catch up.',
                        style: TextStyle(fontSize: 13, color: BillzoColors.darkSlate),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Batch actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${widget.missedRecords.length} Profile(s) with Missed Cycles',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _isProcessing ? null : () => _setAllActions(MissedResolutionAction.generateAll),
                        child: const Text('All: Generate All'),
                      ),
                      OutlinedButton(
                        onPressed: _isProcessing ? null : () => _setAllActions(MissedResolutionAction.generateDrafts),
                        child: const Text('All: Drafts Only'),
                      ),
                      OutlinedButton(
                        onPressed: _isProcessing ? null : () => _setAllActions(MissedResolutionAction.skipAll),
                        child: const Text('All: Skip'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Per-profile card list
              ...widget.missedRecords.map((record) {
                final currentAction = _selectedActions[record.profile.id] ?? MissedResolutionAction.generateAll;
                final formattedDates = record.missedDates.map((d) => dateFormat.format(d)).join(', ');

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BillzoColors.neutralBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.profile.profileName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Customer: ${record.profile.customerName ?? 'Customer'} | Frequency: ${record.profile.frequency.displayName}',
                                  style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${record.missedCyclesCount} cycle(s) missed',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scheduled Dates: $formattedDates',
                        style: const TextStyle(fontSize: 12, color: BillzoColors.darkSlate),
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      // Action Dropdown
                      Row(
                        children: [
                          const Text('Resolution Action:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: BillzoColors.neutralBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<MissedResolutionAction>(
                                  value: currentAction,
                                  isExpanded: true,
                                  items: const [
                                    DropdownMenuItem(
                                      value: MissedResolutionAction.generateAll,
                                      child: Text('Generate all missed invoices'),
                                    ),
                                    DropdownMenuItem(
                                      value: MissedResolutionAction.generateLatestOnly,
                                      child: Text('Generate latest invoice only (skip prior)'),
                                    ),
                                    DropdownMenuItem(
                                      value: MissedResolutionAction.generateDrafts,
                                      child: Text('Generate drafts for review'),
                                    ),
                                    DropdownMenuItem(
                                      value: MissedResolutionAction.skipAll,
                                      child: Text('Skip all missed cycles'),
                                    ),
                                  ],
                                  onChanged: _isProcessing
                                      ? null
                                      : (val) {
                                          if (val != null) {
                                            setState(() {
                                              _selectedActions[record.profile.id] = val;
                                            });
                                          }
                                        },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Remind Me Later'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _processCatchUp,
          style: ElevatedButton.styleFrom(
            backgroundColor: BillzoColors.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Execute Catch-up'),
        ),
      ],
    );
  }
}
