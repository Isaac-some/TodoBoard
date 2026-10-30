import { defineConfig } from 'vitepress'
export default defineConfig({
  lang: 'zh-CN', title: 'TodoBoard 开发者文档', description: '把资料、记忆、待办与 Agent 执行串成可复现的个人工作链路',
  base: '/TodoBoard/', cleanUrls: true, lastUpdated: true,
  themeConfig: {
    siteTitle: 'TodoBoard', nav: [{text:'开始使用',link:'/zh/quickstart'},{text:'工作链路',link:'/zh/architecture'},{text:'GitHub',link:'https://github.com/Isaac-some/TodoBoard'}],
    sidebar: [{text:'开始',items:[{text:'介绍',link:'/'},{text:'快速开始',link:'/zh/quickstart'},{text:'架构与路线',link:'/zh/architecture'},{text:'配置',link:'/zh/configuration'}]},
      {text:'资料与任务',items:[{text:'资料留存',link:'/zh/sources'},{text:'卡片引用与背景检索',link:'/zh/references'},{text:'主动与自动候选',link:'/zh/candidates'},{text:'结果与人工验收',link:'/zh/results'}]},
      {text:'接入',items:[{text:'OpenViking',link:'/zh/openviking'},{text:'Codex CLI / GUI 与 harness',link:'/zh/codex'},{text:'飞书与权限矩阵',link:'/zh/feishu'},{text:'Agent 与知识库扩展',link:'/zh/extensions'},{text:'版本化协议',link:'/zh/protocols'}]},
      {text:'维护',items:[{text:'后台运维',link:'/zh/operations'},{text:'故障排查',link:'/zh/troubleshooting'},{text:'构建与发布',link:'/zh/releasing'},{text:'验证记录',link:'/zh/validation'}]}],
    search: {provider:'local'}, socialLinks:[{icon:'github',link:'https://github.com/Isaac-some/TodoBoard'}],
    footer:{message:'源码与文档 MIT；外部依赖保留各自许可证。',copyright:'TodoBoard contributors'}
  }
})
