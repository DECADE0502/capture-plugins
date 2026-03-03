# Capture Plugins

OrCAD Capture CIS 23.1 TCL 插件仓库。

配合 [Capture 插件管理器](https://github.com/DECADE0502/capture-plugin-manager) 使用，在管理器中点击 **「仓库同步」** 即可浏览并一键安装。

---

## 插件列表

| 插件 | 版本 | 快捷键 | 说明 |
|------|------|--------|------|
| **NCC Property Marker** | 1.0.0 | `Ctrl+Q` | 选中器件后标记为 NC：添加 NCC=NC 属性，显示 NC 文字，器件变灰 |
| **Hide All Value Display** | 1.0.0 | — | 一键隐藏当前工程中所有元件的 Value 属性显示 |

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
