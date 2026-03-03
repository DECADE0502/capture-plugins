# Capture Plugins

OrCAD Capture CIS 23.1 TCL 插件仓库。

配合 [Capture 插件管理器](https://github.com/DECADE0502/capture-plugin-manager) 使用，在管理器中点击 **「仓库同步」** 即可浏览并一键安装。

---

## 插件列表

| 插件 | 版本 | 快捷键 | 说明 |
|------|------|--------|------|
| **NCC Property Marker** | 1.0.0 | `Ctrl+Q` | 选中器件后标记为 NC：添加 NCC=NC 属性，显示 NC 文字，器件变灰 |
| **Hide All Value Display** | 1.0.0 | — | 一键隐藏当前工程中所有元件的 Value 属性显示 |
| **Publish Design (Normal)** | 1.0.0 | — | 自动处理所有 NCC=NC 器件（变灰+显示NC），另存 DSN 文件加时间戳 |
| **Publish PDF (Hide Value)** | 1.0.0 | — | 隐藏所有 Value 后提示用户导出 PDF，完成后可一键恢复 Value 显示 |

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

### Hide All Value Display (`capHideValue.tcl`)

批量隐藏工程中所有元件的 Value 属性显示。适用于以下场景：

- 原理图导出 PDF 前清理多余标注
- 工程模板初始化时统一隐藏 Value
- 图纸排版优化

**使用方法**：从菜单 `Tools > Hide All Values` 执行，操作完成后 `Ctrl+S` 保存。

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

### Publish PDF — PDF 发布 (`capPublishPDF.tcl`)

分两步完成「隐藏 Value → 导出 PDF → 恢复 Value」的工作流：

**第一步：隐藏 Value 并准备导出**
- 自动隐藏所有元件的 Value 属性显示
- 在内存中保存所有隐藏状态，用于后续恢复
- 弹出提示，指引用户手动执行 `File → Export → PDF`

**第二步：恢复 Value 显示**
- PDF 导出完成后，从菜单执行恢复操作
- 自动重建所有被隐藏的 Value 显示属性
- 设计恢复到隐藏前的状态

适用场景：
- 需要生成不带阻值/容值标注的简洁 PDF 文档
- 原理图外发给客户或供应商时隐藏敏感参数

**使用方法**：
1. `Tools > Publish PDF (Hide Value)` — 隐藏所有 Value
2. 手动 `File → Export → PDF` 导出
3. `Tools > Restore Value Display` — 恢复所有 Value

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
