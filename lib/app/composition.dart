/// 组合根决策（纯函数，可单测）。
///
/// 关键安全不变量：
/// 1. 持久化后端只由「运行平台 + 沙箱目录可用性」决定，**不依赖** OCR/分享/提醒
///    capability 握手——否则握手超时/失败会让 OHOS 静默降级内存仓库、丢数据。
/// 2. OHOS 运行期缺少沙箱目录 → 阻塞错误，禁止静默用内存。
/// 3. Release（isDebug=false）绝不启用 Mock 网关。
library;

/// 持久化后端选择。
enum PersistenceChoice {
  /// OHOS 运行期：必须使用持久 SQL 仓库。
  ohosSql,

  /// 桌面/测试：内存仓库（仅开发降级，Release 走不到）。
  devMemory,

  /// OHOS 运行期但沙箱目录缺失：阻塞错误，禁止静默降级内存。
  ohosBlockedNoSandbox,
}

/// 依据运行平台与沙箱目录决定持久化后端。
///
/// [operatingSystem] 取自 `Platform.operatingSystem`（OHOS Flutter 引擎返回
/// `'ohos'`），这是与 capability 握手无关的构建/运行期信号。
PersistenceChoice choosePersistence({
  required String operatingSystem,
  required String? sandboxDir,
}) {
  if (operatingSystem != 'ohos') return PersistenceChoice.devMemory;
  if (sandboxDir == null || sandboxDir.isEmpty) {
    return PersistenceChoice.ohosBlockedNoSandbox;
  }
  return PersistenceChoice.ohosSql;
}

/// 是否使用 Mock 网关。
///
/// Release（[isDebug]=false）恒为 false，即使显式传入 [forceMock]=true 也不启用，
/// 从而杜绝 Release 静默 Mock。桥接缺席且处于 Debug 时才默认 Mock。
bool shouldUseMockGateways({
  required bool bridged,
  required bool isDebug,
  bool? forceMock,
}) {
  if (!isDebug) return false;
  if (forceMock != null) return forceMock;
  return !bridged;
}
