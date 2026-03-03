#############################################################################
# capPublishPDF.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Publish as PDF (Hide Value)
# @Version:      1.0.0
# @Author:       KAIDOU.WU
# @Menu:         Tools > Publish PDF (Hide Value) / Restore Value Display
# @Description:  隐藏所有Value后提示用户导出PDF，完成后可恢复Value显示
#############################################################################

namespace eval ::capPublishPDF {
    # Store original Value display state for restore
    # Key: "$pageIdx,$instIdx" -> list of {propName displayType color locationX locationY rotation}
    variable savedValueProps
    array set savedValueProps {}
    variable hasSavedState 0
}

proc capPublishPDF_shouldProcess {args} {
    return true
}

proc capPublishPDF_enable {args} {
    return true
}

proc capPublishPDF_restoreEnable {args} {
    return $::capPublishPDF::hasSavedState
}

# ======================================================================
# Hide All Values and prompt user to export PDF
# ======================================================================
proc capPublishPDF_execute {} {

    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == "NULL"} {
        tk_messageBox -icon error -title "Publish PDF" \
            -message "没有打开的设计文件。\nNo active design."
        return
    }

    # Clear any previously saved state
    array unset ::capPublishPDF::savedValueProps
    array set ::capPublishPDF::savedValueProps {}
    set ::capPublishPDF::hasSavedState 0

    puts "Publish PDF: Scanning all pages to hide Value display..."

    set totalCount 0
    set hiddenCount 0
    set errorCount 0

    set lStatus [DboState]
    set objSchematic [$objDesign GetRootSchematic $lStatus]

    if {$objSchematic == "" || $objSchematic == "NULL"} {
        tk_messageBox -icon error -title "Publish PDF" \
            -message "无法获取原理图。\nCannot get root schematic."
        return
    }

    set pageIdx 0
    set lStatus [DboState]
    set objPageIter [$objSchematic NewPagesIter $lStatus]
    set lStatus [DboState]
    set objPage [$objPageIter NextPage $lStatus]

    while {$objPage != "NULL" && $objPage != ""} {

        set instIdx 0
        set lStatus [DboState]
        set objInstIter [$objPage NewPartInstsIter $lStatus]
        set lStatus [DboState]
        set objInst [$objInstIter NextPartInst $lStatus]

        while {$objInst != "NULL" && $objInst != ""} {
            incr totalCount

            set lStatus [DboState]
            set objDispIter [$objInst NewDisplayPropsIter $lStatus]
            set lStatus [DboState]
            set objDP [$objDispIter NextProp $lStatus]

            while {$objDP != "NULL" && $objDP != ""} {
                set csName [OrTclObj_CString ""]
                catch {$objDP GetName $csName}
                set dpName [DboTclHelper_sGetConstCharPtr $csName]

                if {$dpName == "Value"} {
                    # Save state before deleting
                    set lDispColor 0
                    catch {set lDispColor [$objDP GetColor $lStatus]}
                    set lDispType 0
                    catch {set lDispType [$objDP GetDisplayType $lStatus]}

                    # Save the instance reference name as key for restore
                    set lInstName [DboTclHelper_sMakeCString ""]
                    catch {$objInst GetName $lInstName}
                    set lInstNameStr [DboTclHelper_sGetConstCharPtr $lInstName]

                    set key "${pageIdx},${lInstNameStr}"
                    set ::capPublishPDF::savedValueProps($key) [list $lDispColor $lDispType]

                    # Delete the display prop (hide it)
                    if {[catch {
                        $objInst DeleteDisplayProp $objDP
                        incr hiddenCount
                    } errMsg]} {
                        incr errorCount
                    }
                    break
                }

                set lStatus [DboState]
                set objDP [$objDispIter NextProp $lStatus]
            }

            incr instIdx
            set lStatus [DboState]
            set objInst [$objInstIter NextPartInst $lStatus]
        }

        incr pageIdx
        set lStatus [DboState]
        set objPage [$objPageIter NextPage $lStatus]
    }

    $lStatus -delete

    if {$hiddenCount > 0} {
        set ::capPublishPDF::hasSavedState 1
    }

    puts "Publish PDF: Done. Total=$totalCount Hidden=$hiddenCount Errors=$errorCount"

    # Prompt user
    tk_messageBox -icon info -title "Publish PDF - Value已隐藏" \
        -message "已隐藏 $hiddenCount 个器件的 Value 显示。\n\n请现在手动导出PDF：\n  File → Export → PDF\n\n导出完成后，使用菜单：\n  Tools → Restore Value Display\n来恢复所有Value显示。\n\n注意：恢复前请勿保存设计！"
}

# ======================================================================
# Restore All Value Display Props
# ======================================================================
proc capPublishPDF_restore {} {

    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == "NULL"} {
        tk_messageBox -icon error -title "Restore Value" \
            -message "没有打开的设计文件。\nNo active design."
        return
    }

    if {$::capPublishPDF::hasSavedState == 0} {
        tk_messageBox -icon warning -title "Restore Value" \
            -message "没有需要恢复的Value状态。\n请先使用 Publish PDF (Hide Value) 功能。"
        return
    }

    puts "Restore Value: Re-adding Value display props..."

    set lStatus [DboState]
    set objSchematic [$objDesign GetRootSchematic $lStatus]

    if {$objSchematic == "" || $objSchematic == "NULL"} {
        tk_messageBox -icon error -title "Restore Value" \
            -message "无法获取原理图。\nCannot get root schematic."
        return
    }

    set lValueNameCS [DboTclHelper_sMakeCString "Value"]
    set lNullObj "NULL"
    set restoreCount 0
    set errorCount 0

    set pageIdx 0
    set lStatus [DboState]
    set objPageIter [$objSchematic NewPagesIter $lStatus]
    set lStatus [DboState]
    set objPage [$objPageIter NextPage $lStatus]

    while {$objPage != $lNullObj && $objPage != ""} {

        set lStatus [DboState]
        set objInstIter [$objPage NewPartInstsIter $lStatus]
        set lStatus [DboState]
        set objInst [$objInstIter NextPartInst $lStatus]

        while {$objInst != $lNullObj && $objInst != ""} {

            set lInstName [DboTclHelper_sMakeCString ""]
            catch {$objInst GetName $lInstName}
            set lInstNameStr [DboTclHelper_sGetConstCharPtr $lInstName]

            set key "${pageIdx},${lInstNameStr}"

            if {[info exists ::capPublishPDF::savedValueProps($key)]} {
                set savedInfo $::capPublishPDF::savedValueProps($key)
                set savedColor [lindex $savedInfo 0]
                set savedType [lindex $savedInfo 1]

                # Check if Value display prop already exists (shouldn't, but safety)
                set existingDP [$objInst GetDisplayProp $lValueNameCS $lStatus]
                if {$existingDP == $lNullObj} {
                    # Re-create the display prop for "Value"
                    if {[catch {
                        set lPropLoc [DboTclHelper_sMakeCPoint 0 20]
                        set lLogFont [DboTclHelper_sMakeLOGFONT]
                        set lRotation 0
                        set lColor $savedColor
                        if {$lColor == 0} { set lColor $DEFAULT_COLOR }

                        set newDP [$objInst NewDisplayProp \
                            $lStatus $lValueNameCS $lPropLoc $lRotation $lLogFont $lColor]

                        if {$newDP != $lNullObj} {
                            DboDisplayProp -this $newDP
                            # Display type: 0=name&value, 1=value only, 2=name only, 3=both
                            $newDP SetDisplayType 1
                            incr restoreCount
                        }
                    } errMsg]} {
                        incr errorCount
                        puts "Restore Value: Error restoring $lInstNameStr: $errMsg"
                    }
                }
            }

            set lStatus [DboState]
            set objInst [$objInstIter NextPartInst $lStatus]
        }

        incr pageIdx
        set lStatus [DboState]
        set objPage [$objPageIter NextPage $lStatus]
    }

    DboTclHelper_sDeleteCString $lValueNameCS
    $lStatus -delete

    # Clear saved state
    array unset ::capPublishPDF::savedValueProps
    array set ::capPublishPDF::savedValueProps {}
    set ::capPublishPDF::hasSavedState 0

    puts "Restore Value: Done. Restored=$restoreCount Errors=$errorCount"

    if {$restoreCount > 0} {
        tk_messageBox -icon info -title "Restore Value" \
            -message "已恢复 $restoreCount 个器件的 Value 显示。\n\n请 Ctrl+S 保存设计。"
    } else {
        tk_messageBox -icon warning -title "Restore Value" \
            -message "没有Value被恢复。可能所有器件原本就没有Value显示。"
    }
}

proc capPublishPDF_register {} {
    # Hide Value for PDF export
    RegisterAction "_cdnCapActionPublishPDF" "capPublishPDF_shouldProcess" "" "capPublishPDF_execute" ""
    RegisterAction "_cdnCapUpdatePublishPDF" "capPublishPDF_shouldProcess" "" "capPublishPDF_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsPublishPDF"] "" "" [list "action" "Publish PDF (&Hide Value)" "0" "_cdnCapActionPublishPDF" "_cdnCapUpdatePublishPDF" "" "" "" "Hide all Value display for PDF export"] ""]

    # Restore Value display
    RegisterAction "_cdnCapActionRestoreValue" "capPublishPDF_shouldProcess" "" "capPublishPDF_restore" ""
    RegisterAction "_cdnCapUpdateRestoreValue" "capPublishPDF_shouldProcess" "" "capPublishPDF_restoreEnable" ""
    InsertXMLMenu [list [list "Tools" "ToolsRestoreValue"] "" "" [list "action" "&Restore Value Display" "0" "_cdnCapActionRestoreValue" "_cdnCapUpdateRestoreValue" "" "" "" "Restore Value display after PDF export"] ""]
}

capPublishPDF_register
