# 后台运维

所有命令都使用同一数据目录，可通过全局参数 `--data-dir` 或环境变量 `TODOBOARD_DATA_DIR` 指定。

```bash
cd ~/Projects/TodoBoard
.venv/bin/todoboardctl start
.venv/bin/todoboardctl status
.venv/bin/todoboardctl doctor
.venv/bin/todoboardctl stop
.venv/bin/todoboardctl run-once
```

start 安装当前用户的 LaunchAgent，Label 带数据目录哈希。它与其他实例、原个人环境分别运行。退出 Board 不会停止它；登录后自动启动，休眠恢复后继续轮询。stop 停止对应 Label 并移除该实例的登录注册，保留资料、卡片和游标。run-once 遇到已有后台时报告 `worker-already-running`，避免并发处理同一队列。

后台每轮核对显式目录、飞书覆盖范围、inbox、归档任务和 GUI 结果。资料失败后保留队列，默认一分钟后重试。飞书使用成功覆盖游标，保留一天重叠窗口处理迟到资料；离线或缺权限不前移游标。

`materials/` 是原文与来源 metadata，`inbox/` 是 Hook 待处理事件，`.processed` 是已接收凭据，`runtime.sqlite` 保存队列，`deliveries/` 保存执行轨迹，`logs/` 是当前实例日志。`worker-status.json` 记录最后一轮和错误状态。

更改配置后后台下一轮重新读取。更改 Python 或仓库位置后，重跑安装器与 start 更新可执行路径。迁移数据时先 stop 并退出 App，再整体备份数据目录；不要只复制 SQLite 主文件而丢弃 WAL。
