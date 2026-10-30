# 卡片引用与背景检索

`createdAt` 是卡片实际添加时间。`sourceRefs[].observedAt` 是原始事件或资料记录时间，二者不会因为拖动卡片而改变。

引用包含 `id`、`kind`、`title`、`uri`、`observedAt`、`contentHash` 和 `locator`。`uri` 定位知识库原文；`locator` 标注行动项所在段落或原文引句；哈希标明资料版本。来源原始地址也保留在后台 metadata 的 `sourceURI`。

分发之前，后台沿引用读取原文，再用标题、备注与时间在配置的检索位置补查。结果附带 URI；读取失败会记录缺失项，已留存的本地版本可以作为回退。背景是资料，不能给 Agent 增加工具权限或替代用户指令。

执行中，Agent 可以通过 TodoBoard MCP 的 `knowledge_search`、`knowledge_read` 续查，也可以使用自行配置的官方 OV MCP。所有入口应指向同一服务、身份及检索位置。

```bash
cd ~/Projects/TodoBoard
.venv/bin/todoboardctl context CARD_ID
```

卡片详情可以复制来源 URI、查看原始时间与对应段落。后端不会用相似搜索结果偷偷替换原始证据。
