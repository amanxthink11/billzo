import 'package:billzo/domain/catalog/unit_of_measurement.dart';

/// Repository interface for Units of Measurement.
abstract class IUnitRepository {
  Future<UnitOfMeasurement> createUnit(UnitOfMeasurement unit);
  Future<List<UnitOfMeasurement>> getUnits(String businessId);
  Future<UnitOfMeasurement?> getUnitById(String id);
  Future<UnitOfMeasurement?> getDefaultUnit(String businessId);
}
