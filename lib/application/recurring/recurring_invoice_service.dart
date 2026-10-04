import 'package:uuid/uuid.dart';

import 'package:billzo/application/invoice/invoice_service.dart';
import 'package:billzo/domain/business/business_repository.dart';
import 'package:billzo/domain/catalog/tax_rate_repository.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party_repository.dart';
import 'package:billzo/domain/recurring/recurring_execution_status.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_execution.dart';
import 'package:billzo/domain/recurring/recurring_invoice_repository.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/domain/recurring/recurring_invoice_validator.dart';

/// Resolution action chosen by the merchant for missed recurring invoice schedules.
enum MissedResolutionAction {
  generateAll,
  generateLatestOnly,
  generateDrafts,
  skipAll,
}

/// Discovered missed schedule milestone for a profile.
class MissedScheduleRecord {
  final RecurringInvoice profile;
  final List<DateTime> missedDates;

  const MissedScheduleRecord({
    required this.profile,
    required this.missedDates,
  });

  int get missedCyclesCount => missedDates.length;
}

/// Resolution instruction for a specific recurring invoice profile.
class MissedScheduleResolution {
  final String profileId;
  final MissedResolutionAction action;

  const MissedScheduleResolution({
    required this.profileId,
    required this.action,
  });
}

/// Service orchestrating recurring billing schedules, offline catch-up, and idempotent invoice execution.
class RecurringInvoiceService {
  final IRecurringInvoiceRepository recurringRepo;
  final InvoiceService invoiceService;
  final IPartyRepository partyRepo;
  final IBusinessRepository businessRepo;
  final ITaxRateRepository taxRateRepo;

  IRecurringInvoiceRepository get _recurringRepo => recurringRepo;
  InvoiceService get _invoiceService => invoiceService;
  IPartyRepository get _partyRepo => partyRepo;
  IBusinessRepository get _businessRepo => businessRepo;
  ITaxRateRepository get _taxRateRepo => taxRateRepo;

  static const _uuid = Uuid();

  RecurringInvoiceService({
    required this.recurringRepo,
    required this.invoiceService,
    required this.partyRepo,
    required this.businessRepo,
    required this.taxRateRepo,
  });

  Future<RecurringInvoice> createProfile(RecurringInvoice profile) {
    final errors = RecurringInvoiceValidator.validate(profile);
    if (errors.isNotEmpty) {
      throw ArgumentError('Recurring invoice validation failed: ${errors.join(', ')}');
    }
    return _recurringRepo.createProfile(profile);
  }

  Future<RecurringInvoice> updateProfile(RecurringInvoice profile) {
    final errors = RecurringInvoiceValidator.validate(profile);
    if (errors.isNotEmpty) {
      throw ArgumentError('Recurring invoice validation failed: ${errors.join(', ')}');
    }
    return _recurringRepo.updateProfile(profile);
  }

  Future<void> pauseProfile(String profileId) async {
    final profile = await _recurringRepo.getProfileById(profileId);
    if (profile == null) throw ArgumentError('Recurring profile not found: $profileId');
    RecurringInvoiceValidator.checkStatusTransition(profile.status, RecurringInvoiceStatus.paused);
    await _recurringRepo.updateStatus(profileId, RecurringInvoiceStatus.paused);
  }

  Future<void> resumeProfile(String profileId) async {
    final profile = await _recurringRepo.getProfileById(profileId);
    if (profile == null) throw ArgumentError('Recurring profile not found: $profileId');
    RecurringInvoiceValidator.checkStatusTransition(profile.status, RecurringInvoiceStatus.active);
    await _recurringRepo.updateStatus(profileId, RecurringInvoiceStatus.active);
  }

  Future<void> cancelProfile(String profileId) async {
    final profile = await _recurringRepo.getProfileById(profileId);
    if (profile == null) throw ArgumentError('Recurring profile not found: $profileId');
    RecurringInvoiceValidator.checkStatusTransition(profile.status, RecurringInvoiceStatus.cancelled);
    await _recurringRepo.updateStatus(profileId, RecurringInvoiceStatus.cancelled);
  }

  Future<void> deleteProfile(String profileId) {
    return _recurringRepo.deleteProfile(profileId);
  }

  Future<RecurringInvoice?> getProfileById(String id) {
    return _recurringRepo.getProfileById(id);
  }

  Future<List<RecurringInvoice>> getProfilesByBusiness(
    String businessId, {
    RecurringInvoiceStatus? statusFilter,
  }) {
    return _recurringRepo.getProfilesByBusiness(businessId, statusFilter: statusFilter);
  }

  Future<List<RecurringInvoice>> getDueProfiles(String businessId, DateTime asOfDate) {
    return _recurringRepo.getDueProfiles(businessId, asOfDate);
  }

  Future<List<RecurringInvoiceExecution>> getExecutions(String recurringInvoiceId) {
    return _recurringRepo.getExecutions(recurringInvoiceId);
  }

  /// Atomically generates an invoice for a scheduled cycle date, enforcing idempotency.
  /// If already executed for [scheduledDate], returns null.
  Future<Invoice?> generateInvoiceForCycle(
    RecurringInvoice profile,
    DateTime scheduledDate, {
    bool? overrideAsFinalized,
  }) async {
    final alreadyExecuted = await _recurringRepo.hasExecutionForDate(profile.id, scheduledDate);
    if (alreadyExecuted) {
      return null;
    }

    final customer = await _partyRepo.getPartyById(profile.customerId);
    if (customer == null) {
      throw StateError('Cannot generate recurring invoice: Customer ${profile.customerId} not found.');
    }

    final business = await _businessRepo.getActiveBusiness();
    if (business == null || business.id != profile.businessId) {
      throw StateError('Cannot generate recurring invoice: Business ${profile.businessId} not active.');
    }

    final isIntraState = business.stateCode.trim() == (customer.billingStateCode?.trim() ?? business.stateCode.trim());
    final invoiceId = _uuid.v4();
    final now = DateTime.now();

    int totalSubtotal = 0;
    int totalTaxable = 0;
    int totalCgst = 0;
    int totalSgst = 0;
    int totalIgst = 0;

    final invoiceItems = <InvoiceItem>[];

    for (final item in profile.items) {
      final taxRate = await _taxRateRepo.getTaxRateById(item.taxRateId);
      final rateBasisPoints = taxRate?.rateBasisPoints ?? 0;

      final grossPaise = item.ratePaise * item.quantity;
      final discountPaise = item.discountPaise;
      final lineTaxable = (grossPaise - discountPaise) > 0 ? (grossPaise - discountPaise) : 0;

      int cgstBasis = 0;
      int sgstBasis = 0;
      int igstBasis = 0;
      int cgstAmount = 0;
      int sgstAmount = 0;
      int igstAmount = 0;

      if (isIntraState) {
        cgstBasis = rateBasisPoints ~/ 2;
        sgstBasis = rateBasisPoints - cgstBasis;
        cgstAmount = (lineTaxable * cgstBasis) ~/ 10000;
        sgstAmount = (lineTaxable * sgstBasis) ~/ 10000;
      } else {
        igstBasis = rateBasisPoints;
        igstAmount = (lineTaxable * igstBasis) ~/ 10000;
      }

      final lineTotal = lineTaxable + cgstAmount + sgstAmount + igstAmount;

      totalSubtotal += grossPaise;
      totalTaxable += lineTaxable;
      totalCgst += cgstAmount;
      totalSgst += sgstAmount;
      totalIgst += igstAmount;

      invoiceItems.add(
        InvoiceItem(
          id: _uuid.v4(),
          invoiceId: invoiceId,
          productId: item.productId,
          taxRateId: item.taxRateId,
          productName: item.productName,
          hsnSac: item.hsnSac,
          quantityScaled: item.quantity,
          unitCode: item.unitCode,
          ratePaise: item.ratePaise,
          mrpPaise: item.ratePaise,
          discountPaise: discountPaise,
          taxableAmountPaise: lineTaxable,
          cgstRateBasisPoints: cgstBasis,
          cgstAmountPaise: cgstAmount,
          sgstRateBasisPoints: sgstBasis,
          sgstAmountPaise: sgstAmount,
          igstRateBasisPoints: igstBasis,
          igstAmountPaise: igstAmount,
          totalAmountPaise: lineTotal,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final totalAmountPaise = totalTaxable + totalCgst + totalSgst + totalIgst;
    final dueDate = scheduledDate.add(Duration(days: profile.paymentTermsDays));

    final invoice = Invoice(
      id: invoiceId,
      businessId: profile.businessId,
      customerId: profile.customerId,
      recurringInvoiceId: profile.id,
      invoiceNumber: '', // Allocated automatically on finalization or preview on draft
      invoiceDate: scheduledDate,
      dueDate: dueDate,
      placeOfSupplyStateCode: customer.billingStateCode ?? business.stateCode,
      invoiceType: InvoiceType.taxInvoice,
      subtotalPaise: totalSubtotal,
      discountPaise: 0,
      taxableAmountPaise: totalTaxable,
      cgstPaise: totalCgst,
      sgstPaise: totalSgst,
      igstPaise: totalIgst,
      cessPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: totalAmountPaise,
      paidAmountPaise: 0,
      balanceAmountPaise: totalAmountPaise,
      notes: profile.notes != null ? 'Recurring: ${profile.notes}' : 'Generated from recurring profile: ${profile.profileName}',
      items: invoiceItems,
      createdAt: now,
      updatedAt: now,
      customerName: customer.name,
      customerPhone: customer.phone,
      customerGstin: customer.gstin,
      customerCompanyName: customer.companyName,
    );

    final shouldFinalize = overrideAsFinalized ?? (profile.autoGenerate && !profile.requireReview);

    Invoice savedInvoice;
    RecurringExecutionStatus executionStatus;

    if (shouldFinalize) {
      savedInvoice = await _invoiceService.finalizeInvoice(invoice);
      executionStatus = RecurringExecutionStatus.success;
    } else {
      savedInvoice = await _invoiceService.saveDraft(invoice);
      executionStatus = RecurringExecutionStatus.reviewQueued;
    }

    // Record execution log row for idempotency
    await _recurringRepo.recordExecution(
      RecurringInvoiceExecution(
        id: _uuid.v4(),
        recurringInvoiceId: profile.id,
        invoiceId: savedInvoice.id,
        scheduledForDate: scheduledDate,
        executedAt: now,
        executionStatus: executionStatus,
        notes: shouldFinalize ? 'Finalized invoice #${savedInvoice.invoiceNumber}' : 'Created draft invoice for review',
        createdAt: now,
      ),
    );

    // Calculate next run date
    final nextDate = profile.frequency.calculateNextRunDate(
      scheduledDate,
      customIntervalDays: profile.customIntervalDays,
      anchorDay: profile.startDate.day,
    );

    RecurringInvoiceStatus? newStatus;
    if (profile.endDate != null) {
      final endDay = DateTime(profile.endDate!.year, profile.endDate!.month, profile.endDate!.day, 23, 59, 59);
      if (nextDate.isAfter(endDay)) {
        newStatus = RecurringInvoiceStatus.completed;
      }
    }

    await _recurringRepo.updateScheduleDates(
      profile.id,
      nextRunDate: nextDate,
      lastRunDate: scheduledDate,
      newStatus: newStatus,
    );

    return savedInvoice;
  }

  /// Detects all missed schedule milestones for active profiles (e.g. computer was turned off).
  Future<List<MissedScheduleRecord>> detectMissedSchedules(String businessId, {DateTime? asOfDate}) async {
    final effectiveAsOf = asOfDate ?? DateTime.now();
    final asOfDay = DateTime(effectiveAsOf.year, effectiveAsOf.month, effectiveAsOf.day, 23, 59, 59);

    final dueProfiles = await _recurringRepo.getDueProfiles(businessId, effectiveAsOf);
    final missedList = <MissedScheduleRecord>[];

    for (final profile in dueProfiles) {
      final missedDates = <DateTime>[];
      DateTime candidate = DateTime(profile.nextRunDate.year, profile.nextRunDate.month, profile.nextRunDate.day);

      while (!candidate.isAfter(asOfDay)) {
        if (profile.endDate != null) {
          final endDay = DateTime(profile.endDate!.year, profile.endDate!.month, profile.endDate!.day, 23, 59, 59);
          if (candidate.isAfter(endDay)) break;
        }

        final executed = await _recurringRepo.hasExecutionForDate(profile.id, candidate);
        if (!executed) {
          missedDates.add(candidate);
        }

        final next = profile.frequency.calculateNextRunDate(
          candidate,
          customIntervalDays: profile.customIntervalDays,
          anchorDay: profile.startDate.day,
        );
        if (next == candidate) break; // Safeguard against zero advancement
        candidate = DateTime(next.year, next.month, next.day);
      }

      if (missedDates.isNotEmpty) {
        missedList.add(MissedScheduleRecord(profile: profile, missedDates: missedDates));
      }
    }

    return missedList;
  }

  /// Processes missed schedule resolutions selected by the merchant.
  Future<void> processMissedSchedules(
    String businessId,
    List<MissedScheduleResolution> resolutions, {
    DateTime? asOfDate,
  }) async {
    final missedRecords = await detectMissedSchedules(businessId, asOfDate: asOfDate);
    final recordMap = {for (final r in missedRecords) r.profile.id: r};

    for (final res in resolutions) {
      final record = recordMap[res.profileId];
      if (record == null) continue;

      final profile = record.profile;
      final dates = record.missedDates;
      if (dates.isEmpty) continue;

      switch (res.action) {
        case MissedResolutionAction.generateAll:
          for (final date in dates) {
            await generateInvoiceForCycle(profile, date, overrideAsFinalized: profile.autoGenerate);
          }
          break;

        case MissedResolutionAction.generateLatestOnly:
          // Skip older dates
          for (int i = 0; i < dates.length - 1; i++) {
            await _recurringRepo.recordExecution(
              RecurringInvoiceExecution(
                id: _uuid.v4(),
                recurringInvoiceId: profile.id,
                invoiceId: null,
                scheduledForDate: dates[i],
                executedAt: DateTime.now(),
                executionStatus: RecurringExecutionStatus.skipped,
                notes: 'Skipped during missed schedules reconciliation (generate latest only)',
                createdAt: DateTime.now(),
              ),
            );
          }
          // Generate latest
          await generateInvoiceForCycle(profile, dates.last, overrideAsFinalized: profile.autoGenerate);
          break;

        case MissedResolutionAction.generateDrafts:
          for (final date in dates) {
            await generateInvoiceForCycle(profile, date, overrideAsFinalized: false);
          }
          break;

        case MissedResolutionAction.skipAll:
          for (final date in dates) {
            await _recurringRepo.recordExecution(
              RecurringInvoiceExecution(
                id: _uuid.v4(),
                recurringInvoiceId: profile.id,
                invoiceId: null,
                scheduledForDate: date,
                executedAt: DateTime.now(),
                executionStatus: RecurringExecutionStatus.skipped,
                notes: 'Skipped all during missed schedules reconciliation',
                createdAt: DateTime.now(),
              ),
            );
          }
          // Advance next_run_date to next future date
          final nextFuture = profile.frequency.calculateNextRunDate(
            dates.last,
            customIntervalDays: profile.customIntervalDays,
            anchorDay: profile.startDate.day,
          );
          await _recurringRepo.updateScheduleDates(
            profile.id,
            nextRunDate: nextFuture,
            lastRunDate: dates.last,
          );
          break;
      }
    }
  }
}
