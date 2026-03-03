#############################################################################
# capHideValue.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Hide All Value Display
# @Version:      1.0.0
# @Author:       KAIDOU.WU
# @Menu:         Tools > Hide All Values
# @Description:  一键隐藏当前工程中所有元件的 Value 属性显示
#############################################################################

proc capHideValue_shouldProcess {args} {
    return true
}

proc capHideValue_enable {args} {
    return true
}

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

proc capHideValue_register {} {
    RegisterAction "_cdnCapActionHideValue" "capHideValue_shouldProcess" "" "capHideValue_execute" ""
    RegisterAction "_cdnCapUpdateHideValue" "capHideValue_shouldProcess" "" "capHideValue_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsHideAllValues"] "" "" [list "action" "Hide All &Values" "0" "_cdnCapActionHideValue" "_cdnCapUpdateHideValue" "" "" "" "Hide Value display for all components in design"] ""]
}

capHideValue_register
