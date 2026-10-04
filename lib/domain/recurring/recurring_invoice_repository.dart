import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_execution.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';

/// Repository contract for recurring invoice profiles, schedule executions, and idempotency tracking.
abstract class IRecurringInvoiceRepository {
  /// Creates a new recurring invoice profile with its item templates.
  Future<RecurringInvoice> createProfile(RecurringInvoice profile);

  /// Updates an existing profile's template, frequency, and items.
  Future<RecurringInvoice> updateProfile(RecurringInvoice profile);

  /// Retrieves a recurring profile by its unique ID.
  Future<RecurringInvoice?> getProfileById(String id);

  /// Retrieves all profiles belonging to a business, optionally filtered by status.
  Future<List<RecurringInvoice>> getProfilesByBusiness(
    String businessId, {
    RecurringInvoiceStatus? statusFilter,
  });

  /// Retrieves all active profiles where next_run_date <= asOfDate.
  Future<List<RecurringInvoice>> getDueProfiles(String businessId, DateTime asOfDate);

  /// Updates the next and last run dates and optionally marks status as completed.
  Future<void> updateScheduleDates(
    String profileId, {
    required DateTime nextRunDate,
    DateTime? lastRunDate,
    RecurringInvoiceStatus? newStatus,
  });

  /// Updates profile status (ACTIVE, PAUSED, COMPLETED, CANCELLED).
  Future<void> updateStatus(String profileId, RecurringInvoiceStatus status);

  /// Deletes a profile if no executions exist, or cancels it.
  Future<void> deleteProfile(String profileId);

  /// Records an execution milestone for a cycle date (idempotency key).
  Future<RecurringInvoiceExecution> recordExecution(RecurringInvoiceExecution execution);

  /// Checks if an execution already exists for a specific cycle date.
  Future<bool> hasExecutionForDate(String recurringInvoiceId, DateTime scheduledForDate);

  /// Retrieves all execution logs for a profile.
  Future<List<RecurringInvoiceExecution>> getExecutions(String recurringInvoiceId);
}
