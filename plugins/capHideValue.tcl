#############################################################################
# capHideValue.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Hide / Show All Value Display
# @Version:      1.1.0
# @Author:       KAIDOU.WU
# @Menu:         Tools > Hide All Values / Show All Values
# @Description:  一键隐藏或显示当前工程中所有元件的 Value 属性显示
#############################################################################

proc capHideValue_shouldProcess {args} {
    return true
}

proc capHideValue_enable {args} {
    return true
}

# ======================================================================
# Hide All Values — 删除所有元件的 Value 显示属性
# ======================================================================
proc capHideValue_execute {} {

    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == "NULL"} {
        puts "Hide Value: No design open."
        return
    }

    puts "Hide Value: Scanning all pages..."

    set totalCount 0
    set hiddenCount 0
    set errorCount 0

    set lStatus [DboState]
    set objSchematic [$objDesign GetRootSchematic $lStatus]

    if {$objSchematic == "" || $objSchematic == "NULL"} {
        puts "Hide Value: Cannot get root schematic."
        return
    }

    set lStatus [DboState]
    set objPageIter [$objSchematic NewPagesIter $lStatus]

    set lStatus [DboState]
    set objPage [$objPageIter NextPage $lStatus]

    while {$objPage != "NULL" && $objPage != ""} {

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

            set lStatus [DboState]
            set objInst [$objInstIter NextPartInst $lStatus]
        }

        set lStatus [DboState]
        set objPage [$objPageIter NextPage $lStatus]
    }

    $lStatus -delete

    puts "Hide Value: Done. Total=$totalCount Hidden=$hiddenCount Errors=$errorCount"
    if {$hiddenCount > 0} {
        puts "Hide Value: Please save (Ctrl+S)."
    }
}

# ======================================================================
# Show All Values — 为所有元件重新创建 Value 显示属性
# ======================================================================
proc capShowValue_execute {} {

    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == "NULL"} {
        puts "Show Value: No design open."
        return
    }

    puts "Show Value: Scanning all pages..."

    set totalCount 0
    set shownCount 0
    set skipCount 0
    set errorCount 0

    set lNullObj "NULL"
    set lValueNameCS [DboTclHelper_sMakeCString "Value"]

    set lStatus [DboState]
    set objSchematic [$objDesign GetRootSchematic $lStatus]

    if {$objSchematic == "" || $objSchematic == $lNullObj} {
        puts "Show Value: Cannot get root schematic."
        return
    }

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
            incr totalCount

            # Check if Value property exists on this instance
            set lReadVal [DboTclHelper_sMakeCString ""]
            set lGetStatus [$objInst GetEffectivePropStringValue $lValueNameCS $lReadVal]

            if {[$lGetStatus OK] == 1} {
                # Component has a Value property — check if display prop already exists
                set existingDP [$objInst GetDisplayProp $lValueNameCS $lStatus]

                if {$existingDP == $lNullObj} {
                    # No display prop — create one (show value only)
                    if {[catch {
                        set lPropLoc [DboTclHelper_sMakeCPoint 0 20]
                        set lLogFont [DboTclHelper_sMakeLOGFONT]
                        set lRotation 0
                        set lColor 0

                        set newDP [$objInst NewDisplayProp \
                            $lStatus $lValueNameCS $lPropLoc $lRotation $lLogFont $lColor]

                        if {$newDP != $lNullObj} {
                            DboDisplayProp -this $newDP
                            # DisplayType 1 = value only
                            $newDP SetDisplayType 1
                            incr shownCount
                        }
                    } errMsg]} {
                        incr errorCount
                        puts "Show Value: Error on component: $errMsg"
                    }
                } else {
                    incr skipCount
                }
            }

            set lStatus [DboState]
            set objInst [$objInstIter NextPartInst $lStatus]
        }

        set lStatus [DboState]
        set objPage [$objPageIter NextPage $lStatus]
    }

    DboTclHelper_sDeleteCString $lValueNameCS
    $lStatus -delete

    puts "Show Value: Done. Total=$totalCount Shown=$shownCount AlreadyVisible=$skipCount Errors=$errorCount"
    if {$shownCount > 0} {
        puts "Show Value: Please save (Ctrl+S)."
    }
}

# ======================================================================
# Registration — two menu entries under Tools
# ======================================================================
proc capHideValue_register {} {
    RegisterAction "_cdnCapActionHideValue" "capHideValue_shouldProcess" "" "capHideValue_execute" ""
    RegisterAction "_cdnCapUpdateHideValue" "capHideValue_shouldProcess" "" "capHideValue_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsHideAllValues"] "" "" [list "action" "Hide All &Values" "0" "_cdnCapActionHideValue" "_cdnCapUpdateHideValue" "" "" "" "Hide Value display for all components in design"] ""]

    RegisterAction "_cdnCapActionShowValue" "capHideValue_shouldProcess" "" "capShowValue_execute" ""
    RegisterAction "_cdnCapUpdateShowValue" "capHideValue_shouldProcess" "" "capHideValue_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsShowAllValues"] "" "" [list "action" "Show All V&alues" "0" "_cdnCapActionShowValue" "_cdnCapUpdateShowValue" "" "" "" "Show Value display for all components in design"] ""]
}

capHideValue_register
