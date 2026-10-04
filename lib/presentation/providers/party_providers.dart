import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

class PartyTypeFilterNotifier extends Notifier<PartyType?> {
  @override
  PartyType? build() => null;
  void setFilter(PartyType? filter) => state = filter;
}

/// Filter for party type in UI (customer, supplier, or null for all).
final partyTypeFilterProvider =
    NotifierProvider<PartyTypeFilterNotifier, PartyType?>(PartyTypeFilterNotifier.new);

class PartySearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String query) => state = query;
}

/// Search query string for party list.
final partySearchQueryProvider =
    NotifierProvider<PartySearchQueryNotifier, String>(PartySearchQueryNotifier.new);

class SelectedPartyNotifier extends Notifier<Party?> {
  @override
  Party? build() => null;
  void select(Party? party) => state = party;
}

/// Selected party for detail / inspection pane.
final selectedPartyProvider =
    NotifierProvider<SelectedPartyNotifier, Party?>(SelectedPartyNotifier.new);

/// Reactive list of parties filtered by type and search query.
final partiesListProvider = FutureProvider.autoDispose<List<Party>>((ref) async {
  final businessAsync = ref.watch(activeBusinessProvider);
  final business = businessAsync.value;
  if (business == null) return [];

  final typeFilter = ref.watch(partyTypeFilterProvider);
  final searchQuery = ref.watch(partySearchQueryProvider);
  final service = ref.watch(partyServiceProvider);

  return service.getParties(
    businessId: business.id,
    typeFilter: typeFilter,
    searchQuery: searchQuery,
    includeInactive: false,
    limit: 100,
  );
});
