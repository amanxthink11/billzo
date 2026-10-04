import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/application/recurring/recurring_invoice_service.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

class RecurringSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String query) => state = query;
}

/// Search query string provider for recurring invoices list.
final recurringSearchQueryProvider =
    NotifierProvider<RecurringSearchQueryNotifier, String>(RecurringSearchQueryNotifier.new);

class RecurringStatusFilterNotifier extends Notifier<RecurringInvoiceStatus?> {
  @override
  RecurringInvoiceStatus? build() => null;
  void setFilter(RecurringInvoiceStatus? status) => state = status;
}

/// Status filter provider for recurring invoices list.
final recurringStatusFilterProvider =
    NotifierProvider<RecurringStatusFilterNotifier, RecurringInvoiceStatus?>(RecurringStatusFilterNotifier.new);

/// Provider fetching all recurring invoice profiles for a business.
final recurringInvoicesProvider =
    FutureProvider.family<List<RecurringInvoice>, String>((ref, businessId) async {
  final repo = ref.watch(recurringInvoiceRepositoryProvider);
  return repo.getProfilesByBusiness(businessId);
});

/// Filtered list of recurring invoices applying search and status filter.
final filteredRecurringInvoicesProvider =
    Provider.family<List<RecurringInvoice>, String>((ref, businessId) {
  final asyncProfiles = ref.watch(recurringInvoicesProvider(businessId));
  final query = ref.watch(recurringSearchQueryProvider).toLowerCase().trim();
  final statusFilter = ref.watch(recurringStatusFilterProvider);

  return asyncProfiles.maybeWhen(
    data: (profiles) {
      return profiles.where((p) {
        if (statusFilter != null && p.status != statusFilter) {
          return false;
        }
        if (query.isNotEmpty) {
          final matchesName = p.profileName.toLowerCase().contains(query);
          final matchesCustomer = (p.customerName ?? '').toLowerCase().contains(query);
          if (!matchesName && !matchesCustomer) {
            return false;
          }
        }
        return true;
      }).toList();
    },
    orElse: () => <RecurringInvoice>[],
  );
});

/// Summary KPIs for the recurring invoice management view.
class RecurringKpiSummary {
  final int activeProfilesCount;
  final int pausedProfilesCount;
  final int totalMonthlyEquivalentPaise;
  final int dueCount;

  const RecurringKpiSummary({
    required this.activeProfilesCount,
    required this.pausedProfilesCount,
    required this.totalMonthlyEquivalentPaise,
    required this.dueCount,
  });

  Money get totalMonthlyEquivalent => Money.fromPaise(totalMonthlyEquivalentPaise);
}

/// Computes recurring KPIs from active profiles.
final recurringKpisProvider =
    Provider.family<RecurringKpiSummary, String>((ref, businessId) {
  final asyncProfiles = ref.watch(recurringInvoicesProvider(businessId));

  return asyncProfiles.maybeWhen(
    data: (profiles) {
      int active = 0;
      int paused = 0;
      int dueCount = 0;
      int totalMrrPaise = 0;

      for (final p in profiles) {
        if (p.status == RecurringInvoiceStatus.active) {
          active++;
          if (p.isDueTodayOrOverdue) {
            dueCount++;
          }

          // Compute approximate MRR paise integer representation
          switch (p.frequency) {
            case RecurringFrequency.daily:
              totalMrrPaise += p.totalAmountPaise * 30;
              break;
            case RecurringFrequency.weekly:
              totalMrrPaise += (p.totalAmountPaise * 52) ~/ 12;
              break;
            case RecurringFrequency.biWeekly:
              totalMrrPaise += (p.totalAmountPaise * 26) ~/ 12;
              break;
            case RecurringFrequency.monthly:
              totalMrrPaise += p.totalAmountPaise;
              break;
            case RecurringFrequency.quarterly:
              totalMrrPaise += p.totalAmountPaise ~/ 3;
              break;
            case RecurringFrequency.halfYearly:
              totalMrrPaise += p.totalAmountPaise ~/ 6;
              break;
            case RecurringFrequency.yearly:
              totalMrrPaise += p.totalAmountPaise ~/ 12;
              break;
            case RecurringFrequency.custom:
              totalMrrPaise += p.totalAmountPaise;
              break;
          }
        } else if (p.status == RecurringInvoiceStatus.paused) {
          paused++;
        }
      }

      return RecurringKpiSummary(
        activeProfilesCount: active,
        pausedProfilesCount: paused,
        totalMonthlyEquivalentPaise: totalMrrPaise,
        dueCount: dueCount,
      );
    },
    orElse: () => const RecurringKpiSummary(
      activeProfilesCount: 0,
      pausedProfilesCount: 0,
      totalMonthlyEquivalentPaise: 0,
      dueCount: 0,
    ),
  );
});

/// Discovers missed schedules for the business upon login/startup.
final missedSchedulesProvider =
    FutureProvider.family<List<MissedScheduleRecord>, String>((ref, businessId) async {
  final service = ref.watch(recurringInvoiceServiceProvider);
  return service.detectMissedSchedules(businessId);
});
