# Capture Plugins

OrCAD Capture CIS 23.1 TCL 插件仓库。

配合 [Capture 插件管理器](https://github.com/DECADE0502/capture-plugin-manager) 使用，在管理器中点击 **「仓库同步」** 即可浏览并一键安装。

---

## 插件列表

| 插件 | 版本 | 快捷键 | 说明 |
|------|------|--------|------|
| **NCC Property Marker** | 1.0.0 | `Ctrl+Q` | 选中器件后标记为 NC：添加 NCC=NC 属性，显示 NC 文字，器件变灰 |
| **Hide / Show All Value Display** | 1.1.0 | — | 一键隐藏或显示当前工程中所有元件的 Value 属性显示 |
| **Publish Design (Normal)** | 1.0.0 | — | 自动处理所有 NCC=NC 器件（变灰+显示NC），另存 DSN 文件加时间戳 |
| **Power Tree Extractor** | 1.0.0 | — | 提取所有电源网络拓扑数据，导出 JSON 文件用于分析 |

---

## 插件详情

### NCC Property Marker (`capNCCProperty.tcl`)

硬件工程师在原理图评审或调试阶段，经常需要将某些器件标记为 **NC（Not Connected）**。此插件实现：

- 为选中的器件添加 `NCC = NC` 自定义属性
- 在原理图上显示 "NC" 文字标注
- 将器件及标注颜色变为灰色，便于视觉区分
- 支持批量选中多个器件同时操作

**使用方法**：选中一个或多个器件 → 按 `Ctrl+Q`，或从菜单 `Tools > Add NCC Property` 执行。

---

### Hide / Show All Value Display (`capHideValue.tcl`)

批量隐藏或显示工程中所有元件的 Value 属性显示。提供两个菜单入口：

**Hide All Values** — 删除所有元件的 Value 显示属性
- 原理图导出 PDF 前清理多余标注
- 工程模板初始化时统一隐藏 Value
- 图纸排版优化

**Show All Values** — 为所有元件重新创建 Value 显示属性
- 恢复之前隐藏的 Value 显示
- 跳过已有 Value 显示的元件，不会重复创建
- 仅对有 Value 属性的元件生效

**使用方法**：
- `Tools > Hide All Values` — 隐藏所有 Value
- `Tools > Show All Values` — 显示所有 Value
- 操作完成后 `Ctrl+S` 保存

---

### Publish Design — 普通发布 (`capPublishDesign.tcl`)

一键发布原理图设计文件。自动执行以下操作：

1. **扫描所有 NCC=NC 器件** — 自动将已标记 NC 的器件变灰、显示 NC 文字标注
2. **保存当前设计** — 确保最新修改已写入
3. **生成带时间戳的文件名** — 如 `MyDesign_20260303_120000.dsn`
4. **弹出另存为对话框** — 用户选择保存位置，生成独立的发布副本

适用场景：
- 原理图评审前发布正式版本
- 归档带时间戳的设计快照
- 确保所有 NC 器件在发布版本中正确标注

**使用方法**：从菜单 `Tools > Publish Design` 执行。

---

### Power Tree Extractor (`capPowerTree.tcl`)

自动提取原理图中所有电源网络的拓扑数据，生成结构化 JSON 文件，便于后续分析电源树架构。

功能特性：

- **遍历所有 Flat Net** — 扫描设计中全部网络，通过引脚类型（`POWER`）自动识别电源网络
- **提取完整拓扑** — 每个电源网络上的所有连接：器件 RefDes、引脚号、引脚名、引脚类型、Part Name、Value
- **智能分类器件角色** — 自动识别 LDO、DCDC、VREF、SWITCH、CAP、RES 等角色
- **JSON 输出** — 结构化数据，包含设计摘要、器件统计、电源网络详情
- **Console 摘要** — 在 TCL 控制台输出电源网络连接概览

输出 JSON 结构：
```json
{
  "design": "MyDesign.dsn",
  "exportTime": "2026-03-04 12:00:00",
  "totalNets": 500,
  "powerNetCount": 25,
  "componentCount": 120,
  "componentSummary": {"LDO": 3, "DCDC": 2, "CAP": 80, ...},
  "components": {"U1": {"partName": "TPS563200", "value": "", "role": "DCDC"}, ...},
  "powerNets": {
    "VCC_3V3": [
      {"ref": "U1", "pin": "5", "pinName": "VOUT", "pinType": "POWER", ...},
      {"ref": "C10", "pin": "1", "pinName": "1", "pinType": "PASSIVE", ...}
    ]
  }
}
```

适用场景：
- 分析电源树拓扑结构
- 检查电源网络连接完整性
- 为后续 AI 分析或可视化提供数据源

**使用方法**：从菜单 `Tools > Export Power Tree` 执行，选择保存目录后自动导出。

---

## 开发新插件

插件为标准 OrCAD Capture TCL 脚本，放置在 `plugins/` 目录下。

文件头部需包含以下元数据注释，管理器会自动解析：

```tcl
#############################################################################
# yourPlugin.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  插件显示名称
# @Version:      1.0.0
# @Author:       作者
# @Hotkey:       快捷键（可选）
# @Menu:         菜单位置
# @Description:  一句话功能描述
#############################################################################
```

提交 PR 或直接推送到 `plugins/` 目录即可。
