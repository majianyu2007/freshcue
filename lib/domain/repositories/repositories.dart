import '../entities/reminder.dart';
import '../entities/source_asset.dart';
import '../entities/temporal_card.dart';
import '../enums/enums.dart';

/// 卡片仓库。页面不得绕过仓库直接写 SQL。
abstract interface class CardRepository {
  Future<List<TemporalCard>> listByStatus(Set<CardStatus> statuses);
  Future<TemporalCard?> findById(String id);
  Future<void> save(TemporalCard card);
  Future<void> delete(String id);
}

abstract interface class AssetRepository {
  Future<SourceAsset?> findById(String id);
  Future<SourceAsset?> findBySha256(String sha256);
  Future<void> save(SourceAsset asset);
  Future<void> delete(String id);
}

abstract interface class OcrBlockRepository {
  Future<List<OcrBlock>> listByCard(String cardId);
  Future<void> saveAll(String cardId, List<OcrBlock> blocks);
  Future<void> deleteByCard(String cardId);
}

abstract interface class ReminderRepository {
  Future<List<ReminderPlan>> plansByCard(String cardId);
  Future<List<ReminderInstance>> instancesByCard(String cardId);
  Future<List<ReminderInstance>> allScheduledInstances();
  Future<void> savePlans(String cardId, List<ReminderPlan> plans);
  Future<void> saveInstance(ReminderInstance instance);
  Future<void> replaceInstances(String cardId, List<ReminderInstance> instances);
  Future<void> deleteByCard(String cardId);
}

abstract interface class SettingsRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
