import Foundation

/// Runtime data contract refreshed when this version starts.
public enum ReadmeAgentContract {
    public static let readmeMarkdown = """
    # TodoBoard 数据契约

    这是本机的个人看板。AI 从用户表达及有来源的工作记录中识别待办候选，人手动决定状态、排序和丢弃。

    ## 文件

    - `tasks.json`：唯一数据源。AI 只追加候选任务。
    - `board.md`：app 生成的可读镜像，含四列及候选日期分组，不含垃圾桶。
    - `tasks.json.bak`：最近一次成功保存的完整备份，由 app 维护。
    - `archive/`：兼容旧版历史文件；新版不再自动归档或清空。

    ## AI 写入规则

    1. 先读最新的 `tasks.json`，保留已有对象及根字段，只向 `tasks` 数组追加新对象。
    2. 新对象必须 `status: "backlog"`。从用户表达或OV 会话成功提交、会议整理、执行记录中识别有明确行动目标的事项；保留原始来源和时间，只追加候选，不自动接纳、执行或完成。不得把所有背景记录直接转成 Todo。
    3. 每条使用不重复的 id；先检查现有任务（包括 trash），同一来源已收集过就不重复追加。
    4. `createdAt` 写 Todo 实际添加时间，ISO8601 并包含时区，app 按本地日期分组；移动不会改变它。Agent 可围绕此时间检索相似会议或事件作待核验背景。
    5. 来源位置、版本和段落保存在 `sourceRefs`；补充说明及验收条件写到 `notes`；不要声称 app 自己会扫描 commit。
    6. 不修改已有任务的状态、排序、完成时间和内容；不删除任务，不改 day/version。
    7. 合法 JSON 序列化到同目录临时文件后原子替换。多写入者必须对同目录 `tasks.lock` 加排他 flock，保存前重读，避免覆盖并发修改。
    8. app 监听并加载外部修改，自动生成镜像。不要编辑 board.md 或备份。

    ## 任务字段

    | 字段 | 说明 |
    |---|---|
    | id | 唯一字符串，例如 t-q7m2xk |
    | title | 简明事项标题 |
    | priority | high / mid / low，默认 mid |
    | status | backlog 候选；today 待办（兼容旧字段名）；doing 进行中；done 已完成；trash 已丢弃 |
    | tags | 字符串数组，可选 |
    | notes | 备注和来源，可选 |
    | order | 列内手动顺序，由 app 维护；新候选可省略 |
    | createdAt | ISO8601 收集时间，日期分组依据 |
    | doneAt | app 维护的完成时间 |
    | sourceRefs | 来源、原始时间、知识库 URI、段落和内容哈希 |
    | execution | 回传状态、结果摘要和证据；独立于卡片正式状态 |

    追加对象示例（时间使用实际收集时间）：

    ```json
    {
      "id": "t-q7m2xk",
      "title": "确认登录跳转是否符合预期",
      "priority": "mid",
      "status": "backlog",
      "tags": ["验收"],
      "notes": "来源：仓库路径与 commit；验收：登录后进入首页。",
      "createdAt": "2026-10-28T09:30:00+08:00"
    }
    ```

    ## 用户工作流

    候选按日期保留；待办、进行中、已完成均由用户拖动或通过右键菜单操作。
    跨天只更新展示日期，不移动、不清除、不自动完成任何卡片。
    所有阶段都能拖入最右侧垃圾桶。垃圾桶任务保存在 JSON 的 trash 状态，隐藏于看板，避免再次收集。
    当前运行期间可撤销最近一次丢弃；需要找回更早丢弃的事项时，先询问用户。
    数据只存在这台 Mac，没有跨设备同步，也没有自动提醒服务。
    """
}
