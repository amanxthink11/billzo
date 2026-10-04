import 'package:billzo/domain/party/party.dart';

/// Repository contract for Party persistence and ledger operations.
abstract class IPartyRepository {
  /// Creates a new party, validates domain constraints, and posts opening balance journal entry if balance > 0.
  Future<Party> createParty(Party party);

  /// Updates an existing party.
  Future<Party> updateParty(Party party);

  /// Fetches a party by primary key.
  Future<Party?> getPartyById(String id);

  /// Returns paginated parties filtered by type and optional search query.
  Future<List<Party>> getParties({
    required String businessId,
    PartyType? typeFilter,
    String? searchQuery,
    bool includeInactive = false,
    int limit = 50,
    int offset = 0,
  });

  /// Counts matching parties for pagination calculations.
  Future<int> countParties({
    required String businessId,
    PartyType? typeFilter,
    String? searchQuery,
    bool includeInactive = false,
  });

  /// Toggles active/inactive status.
  Future<void> setPartyActiveStatus(String id, bool isActive);

  /// Marks a party as deleted (soft delete).
  Future<void> softDeleteParty(String id);

  /// Posts an opening balance double-entry journal entry according to Indian accounting standards.
  Future<void> recordOpeningBalanceJournalEntry({required Party party});

  /// Checks if a phone number is already registered for this business.
  Future<bool> isPhoneTaken(String businessId, String phone, {String? excludePartyId});

  /// Checks if a GSTIN is already registered for this business.
  Future<bool> isGstinTaken(String businessId, String gstin, {String? excludePartyId});
}
