import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/party/party_repository.dart';

/// Application service orchestrating party lifecycle and business rules.
class PartyService {
  final IPartyRepository _partyRepository;

  PartyService(this._partyRepository);

  Future<Party> createParty(Party party) async {
    return _partyRepository.createParty(party);
  }

  Future<Party> updateParty(Party party) async {
    return _partyRepository.updateParty(party);
  }

  Future<Party?> getPartyById(String id) async {
    return _partyRepository.getPartyById(id);
  }

  Future<List<Party>> getParties({
    required String businessId,
    PartyType? typeFilter,
    String? searchQuery,
    bool includeInactive = false,
    int limit = 50,
    int offset = 0,
  }) async {
    return _partyRepository.getParties(
      businessId: businessId,
      typeFilter: typeFilter,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> countParties({
    required String businessId,
    PartyType? typeFilter,
    String? searchQuery,
    bool includeInactive = false,
  }) async {
    return _partyRepository.countParties(
      businessId: businessId,
      typeFilter: typeFilter,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
    );
  }

  Future<void> deactivateParty(String id) async {
    await _partyRepository.setPartyActiveStatus(id, false);
  }

  Future<void> reactivateParty(String id) async {
    await _partyRepository.setPartyActiveStatus(id, true);
  }

  Future<void> deleteParty(String id) async {
    await _partyRepository.softDeleteParty(id);
  }
}
