# 结果与人工验收

卡片正式状态与执行状态独立：`backlog / today / doing / done / trash` 由用户管理；`execution.state` 表示 `queued / running / needsInput / result / failed`。

CLI 执行保存原始事件轨迹和错误日志在 `deliveries/<requestID>/`。GUI 分发保存 thread ID、队列 submission ID，并由后台读取持久化回合或 Stop Hook 关联结果。结果摘要、证据和阻塞信息显示在卡片详情。

Agent 需要介入时应回传 `needsInput` 及具体阻塞，用户在 Agent 自己的界面处理审批或补充信息。Board 不伪造或绕过执行器授权。

用户回到 Board 检查结果后，手动点击完成或拖入已完成。后台只把具有 `doneAt` 且已有成功结果摘要的卡片提交到知识库的 `accepted/`，包含来源、执行摘要、证据与验收时间。尚未验收的执行轨迹仅作为过程记录。

验收结果首先作为可检索资源保存。启用原生 OV Session 经验提取时，经验是否被提炼由 OV 模型判断，不保证每条完成卡片都会生成经验；来源资源仍可直接检索与阅读。
