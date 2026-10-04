import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/recurring_providers.dart';
import 'package:billzo/presentation/screens/recurring/missed_schedules_dialog.dart';
import 'package:billzo/presentation/screens/recurring/recurring_profile_builder_dialog.dart';

/// Desktop ERP screen for managing recurring invoices, auto-schedules, and catch-up.
class RecurringInvoicesScreen extends ConsumerStatefulWidget {
  final Business business;

  const RecurringInvoicesScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<RecurringInvoicesScreen> createState() =>
      _RecurringInvoicesScreenState();
}

class _RecurringInvoicesScreenState
    extends ConsumerState<RecurringInvoicesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCreateDialog() {
    showDialog(
      context: context,
      builder: (ctx) =>
          RecurringProfileBuilderDialog(businessId: widget.business.id),
    );
  }

  void _openEditDialog(RecurringInvoice profile) {
    showDialog(
      context: context,
      builder: (ctx) => RecurringProfileBuilderDialog(
        businessId: widget.business.id,
        existingProfile: profile,
      ),
    );
  }

  Future<void> _openMissedDialog(List<dynamic> missed) async {
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => MissedSchedulesDialog(
        businessId: widget.business.id,
        missedRecords: missed.cast(),
      ),
    );

    if (count != null && count > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully generated $count recurring invoice(s)!'),
          backgroundColor: BillzoColors.successGreen,
        ),
      );
    }
  }

  Future<void> _runCycleNow(RecurringInvoice profile) async {
    try {
      final service = ref.read(recurringInvoiceServiceProvider);
      final invoice = await service.generateInvoiceForCycle(
        profile,
        profile.nextRunDate,
      );

      ref.invalidate(recurringInvoicesProvider(widget.business.id));
      ref.invalidate(missedSchedulesProvider(widget.business.id));

      if (mounted) {
        final message = invoice != null
            ? 'Generated invoice ${invoice.invoiceNumber} for ${profile.profileName}!'
            : 'Cycle already executed for ${profile.profileName}.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Execution failed: $e'),
            backgroundColor: BillzoColors.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _toggleStatus(RecurringInvoice profile) async {
    try {
      final service = ref.read(recurringInvoiceServiceProvider);
      final newStatus = profile.status == RecurringInvoiceStatus.active
          ? RecurringInvoiceStatus.paused
          : RecurringInvoiceStatus.active;

      final updated = profile.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );

      await service.updateProfile(updated);
      ref.invalidate(recurringInvoicesProvider(widget.business.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${profile.profileName} is now ${newStatus.displayName}.'),
            backgroundColor: BillzoColors.primaryBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status update failed: $e'),
            backgroundColor: BillzoColors.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _cancelProfile(RecurringInvoice profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Recurring Profile?'),
        content: Text(
            'Are you sure you want to cancel "${profile.profileName}"? No further invoices will be scheduled.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep Active')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: BillzoColors.dangerRed,
                foregroundColor: Colors.white),
            child: const Text('Cancel Profile'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final service = ref.read(recurringInvoiceServiceProvider);
        final updated = profile.copyWith(
          status: RecurringInvoiceStatus.cancelled,
          updatedAt: DateTime.now(),
        );
        await service.updateProfile(updated);
        ref.invalidate(recurringInvoicesProvider(widget.business.id));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${profile.profileName} has been cancelled.'),
              backgroundColor: BillzoColors.darkSlate,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cancellation failed: $e'),
              backgroundColor: BillzoColors.dangerRed,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfiles =
        ref.watch(recurringInvoicesProvider(widget.business.id));
    final filteredProfiles =
        ref.watch(filteredRecurringInvoicesProvider(widget.business.id));
    final kpis = ref.watch(recurringKpisProvider(widget.business.id));
    final asyncMissed = ref.watch(missedSchedulesProvider(widget.business.id));
    final currentStatusFilter = ref.watch(recurringStatusFilterProvider);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recurring Invoices',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: BillzoColors.darkSlate,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Automated subscription schedules and offline catch-up',
                    style: TextStyle(
                        fontSize: 13, color: BillzoColors.neutralText),
                  ),
                ],
              ),
              Row(
                children: [
                  // Missed Catch-up button
                  asyncMissed.maybeWhen(
                    data: (missed) {
                      if (missed.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ElevatedButton.icon(
                          onPressed: () => _openMissedDialog(missed),
                          icon: const Icon(Icons.history_toggle_off, size: 18),
                          label: Text('Catch-up (${missed.length} Missed)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BillzoColors.warningOrange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),

                  ElevatedButton.icon(
                    onPressed: _openCreateDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. KPI Cards Row
          Row(
            children: [
              _KpiCard(
                title: 'Active Profiles',
                value: '${kpis.activeProfilesCount}',
                icon: Icons.repeat,
                iconColor: BillzoColors.primaryBlue,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                title: 'Monthly Recurring (MRR)',
                value: kpis.totalMonthlyEquivalent.formatted,
                icon: Icons.currency_rupee,
                iconColor: BillzoColors.successGreen,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                title: 'Due Today / Overdue',
                value: '${kpis.dueCount}',
                icon: Icons.notification_important_outlined,
                iconColor: kpis.dueCount > 0
                    ? BillzoColors.dangerRed
                    : BillzoColors.neutralText,
              ),
              const SizedBox(width: 12),
              _KpiCard(
                title: 'Paused Profiles',
                value: '${kpis.pausedProfilesCount}',
                icon: Icons.pause_circle_outline,
                iconColor: BillzoColors.warningOrange,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Search and Status Filters
          Row(
            children: [
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search recurring profile or customer...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: BillzoColors.neutralBorder),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (val) {
                      ref.read(recurringSearchQueryProvider.notifier).setQuery(val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Filter chips
              Wrap(
                spacing: 8,
                children: [
                  _FilterChip(
                    label: 'All',
                    isSelected: currentStatusFilter == null,
                    onTap: () => ref
                        .read(recurringStatusFilterProvider.notifier)
                        .setFilter(null),
                  ),
                  _FilterChip(
                    label: 'Active',
                    isSelected:
                        currentStatusFilter == RecurringInvoiceStatus.active,
                    onTap: () => ref
                        .read(recurringStatusFilterProvider.notifier)
                        .setFilter(RecurringInvoiceStatus.active),
                  ),
                  _FilterChip(
                    label: 'Paused',
                    isSelected:
                        currentStatusFilter == RecurringInvoiceStatus.paused,
                    onTap: () => ref
                        .read(recurringStatusFilterProvider.notifier)
                        .setFilter(RecurringInvoiceStatus.paused),
                  ),
                  _FilterChip(
                    label: 'Completed',
                    isSelected:
                        currentStatusFilter == RecurringInvoiceStatus.completed,
                    onTap: () => ref
                        .read(recurringStatusFilterProvider.notifier)
                        .setFilter(RecurringInvoiceStatus.completed),
                  ),
                  _FilterChip(
                    label: 'Cancelled',
                    isSelected:
                        currentStatusFilter == RecurringInvoiceStatus.cancelled,
                    onTap: () => ref
                        .read(recurringStatusFilterProvider.notifier)
                        .setFilter(RecurringInvoiceStatus.cancelled),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Data Table Canvas
          Expanded(
            child: asyncProfiles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error loading profiles: $e',
                    style: const TextStyle(color: BillzoColors.dangerRed)),
              ),
              data: (_) {
                if (filteredProfiles.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BillzoColors.neutralBorder),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.repeat,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No recurring invoice profiles found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: BillzoColors.darkSlate,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Set up subscription profiles for clients with automated invoicing cycles.',
                            style: TextStyle(
                                fontSize: 13, color: BillzoColors.neutralText),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _openCreateDialog,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create Recurring Profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BillzoColors.primaryBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BillzoColors.neutralBorder),
                  ),
                  child: ListView.separated(
                    itemCount: filteredProfiles.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: BillzoColors.neutralBorder),
                    itemBuilder: (context, index) {
                      final profile = filteredProfiles[index];
                      final isDue = profile.isDueTodayOrOverdue &&
                          profile.status == RecurringInvoiceStatus.active;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            // Profile Name & Customer
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile.profileName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: BillzoColors.darkSlate,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    profile.customerName ?? 'Customer',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: BillzoColors.neutralText,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Frequency
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${profile.frequency.displayName} (Day ${profile.anchorDayOfMonth})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),

                            // Next Run Date
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  Text(
                                    dateFormat.format(profile.nextRunDate),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isDue
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      color: isDue
                                          ? BillzoColors.dangerRed
                                          : BillzoColors.darkSlate,
                                    ),
                                  ),
                                  if (isDue) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'DUE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: BillzoColors.dangerRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Amount
                            Expanded(
                              flex: 2,
                              child: Text(
                                profile.totalAmount.formatted,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: BillzoColors.darkSlate,
                                ),
                              ),
                            ),

                            // Status Chip
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusBgColor(profile.status),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    profile.status.displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _statusTextColor(profile.status),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Actions
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (action) {
                                switch (action) {
                                  case 'run_now':
                                    _runCycleNow(profile);
                                    break;
                                  case 'toggle_status':
                                    _toggleStatus(profile);
                                    break;
                                  case 'edit':
                                    _openEditDialog(profile);
                                    break;
                                  case 'cancel':
                                    _cancelProfile(profile);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                if (profile.status ==
                                    RecurringInvoiceStatus.active)
                                  const PopupMenuItem(
                                    value: 'run_now',
                                    child: Row(
                                      children: [
                                        Icon(Icons.play_arrow,
                                            size: 16,
                                            color: BillzoColors.successGreen),
                                        SizedBox(width: 8),
                                        Text('Run Cycle Now'),
                                      ],
                                    ),
                                  ),
                                if (profile.status ==
                                        RecurringInvoiceStatus.active ||
                                    profile.status ==
                                        RecurringInvoiceStatus.paused)
                                  PopupMenuItem(
                                    value: 'toggle_status',
                                    child: Row(
                                      children: [
                                        Icon(
                                          profile.status ==
                                                  RecurringInvoiceStatus.active
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          size: 16,
                                          color: BillzoColors.warningOrange,
                                        ),
                                        SizedBox(width: 8),
                                        Text(profile.status ==
                                                RecurringInvoiceStatus.active
                                            ? 'Pause Profile'
                                            : 'Resume Profile'),
                                      ],
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit,
                                          size: 16,
                                          color: BillzoColors.primaryBlue),
                                      SizedBox(width: 8),
                                      Text('Edit Profile'),
                                    ],
                                  ),
                                ),
                                if (profile.status !=
                                    RecurringInvoiceStatus.cancelled)
                                  const PopupMenuItem(
                                    value: 'cancel',
                                    child: Row(
                                      children: [
                                        Icon(Icons.cancel_outlined,
                                            size: 16,
                                            color: BillzoColors.dangerRed),
                                        SizedBox(width: 8),
                                        Text('Cancel Profile'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _statusBgColor(RecurringInvoiceStatus status) {
    switch (status) {
      case RecurringInvoiceStatus.active:
        return Colors.green.shade50;
      case RecurringInvoiceStatus.paused:
        return Colors.orange.shade50;
      case RecurringInvoiceStatus.completed:
        return Colors.blue.shade50;
      case RecurringInvoiceStatus.cancelled:
        return Colors.grey.shade100;
    }
  }

  Color _statusTextColor(RecurringInvoiceStatus status) {
    switch (status) {
      case RecurringInvoiceStatus.active:
        return BillzoColors.successGreen;
      case RecurringInvoiceStatus.paused:
        return BillzoColors.warningOrange;
      case RecurringInvoiceStatus.completed:
        return BillzoColors.primaryBlue;
      case RecurringInvoiceStatus.cancelled:
        return Colors.grey.shade600;
    }
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BillzoColors.neutralBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: BillzoColors.neutralText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: BillzoColors.darkSlate,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? BillzoColors.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? BillzoColors.primaryBlue
                : BillzoColors.neutralBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : BillzoColors.darkSlate,
          ),
        ),
      ),
    );
  }
}
