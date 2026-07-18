import '../../domain/entities/reminder.dart';
import '../../domain/entities/source_asset.dart';
import '../../domain/entities/temporal_card.dart';
import '../../domain/enums/enums.dart';
import '../../domain/repositories/repositories.dart';

/// 内存实现：开发与测试用。Release 构建禁止作为正式存储
/// （main.dart 中有断言防护）。
class MemoryCardRepository implements CardRepository {
  final Map<String, TemporalCard> _store = {};

  @override
  Future<List<TemporalCard>> listByStatus(Set<CardStatus> statuses) async =>
      _store.values.where((c) => statuses.contains(c.status)).toList();

  @override
  Future<TemporalCard?> findById(String id) async => _store[id];

  @override
  Future<void> save(TemporalCard card) async => _store[card.id] = card;

  @override
  Future<void> delete(String id) async => _store.remove(id);
}

class MemoryAssetRepository implements AssetRepository {
  final Map<String, SourceAsset> _store = {};

  @override
  Future<SourceAsset?> findById(String id) async => _store[id];

  @override
  Future<SourceAsset?> findBySha256(String sha256) async {
    for (final a in _store.values) {
      if (a.sha256 == sha256) return a;
    }
    return null;
  }

  @override
  Future<void> save(SourceAsset asset) async => _store[asset.id] = asset;

  @override
  Future<void> delete(String id) async => _store.remove(id);
}

class MemoryOcrBlockRepository implements OcrBlockRepository {
  final Map<String, List<OcrBlock>> _byCard = {};

  @override
  Future<List<OcrBlock>> listByCard(String cardId) async =>
      List.of(_byCard[cardId] ?? const []);

  @override
  Future<void> saveAll(String cardId, List<OcrBlock> blocks) async =>
      _byCard[cardId] = List.of(blocks);

  @override
  Future<void> deleteByCard(String cardId) async => _byCard.remove(cardId);
}

class MemoryReminderRepository implements ReminderRepository {
  final Map<String, List<ReminderPlan>> _plans = {};
  final Map<String, List<ReminderInstance>> _instances = {};

  @override
  Future<List<ReminderPlan>> plansByCard(String cardId) async =>
      List.of(_plans[cardId] ?? const []);

  @override
  Future<List<ReminderInstance>> instancesByCard(String cardId) async =>
      List.of(_instances[cardId] ?? const []);

  @override
  Future<List<ReminderInstance>> allScheduledInstances() async => [
    for (final list in _instances.values)
      ...list.where((i) => i.status == ReminderStatus.scheduled),
  ];

  @override
  Future<void> savePlans(String cardId, List<ReminderPlan> plans) async =>
      _plans[cardId] = List.of(plans);

  @override
  Future<void> saveInstance(ReminderInstance instance) async {
    final list = _instances.putIfAbsent(instance.cardId, () => []);
    final idx = list.indexWhere((i) => i.id == instance.id);
    if (idx >= 0) {
      list[idx] = instance;
    } else {
      list.add(instance);
    }
  }

  @override
  Future<void> replaceInstances(
    String cardId,
    List<ReminderInstance> instances,
  ) async => _instances[cardId] = List.of(instances);

  @override
  Future<void> deleteByCard(String cardId) async {
    _plans.remove(cardId);
    _instances.remove(cardId);
  }
}

class MemorySettingsRepository implements SettingsRepository {
  final Map<String, String> _store = {};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<void> set(String key, String value) async => _store[key] = value;
}
