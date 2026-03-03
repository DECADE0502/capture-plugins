#############################################################################
# capNCCProperty.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  NCC Property Marker
# @Version:      1.0.0
# @Author:       KAIDOU.WU
# @Hotkey:       Ctrl+Q
# @Menu:         Tools > Add NCC Property
# @Description:  选中器件Ctrl+Q标记NC：添加NCC=NC属性，显示NC文字，变灰
#############################################################################

proc capNCCProperty_shouldProcess {args} {
    return true
}

proc capNCCProperty_enable {args} {
    return true
}

proc capNCCProperty_execute {} {

    set PROP_NAME  "NCC"
    set PROP_VALUE "NC"
    set GREY_COLOR  45

    set lStatus [DboState]
    set lNullObj "NULL"
    set lCount 0
    set lErrCount 0

    set lSelObjs [GetSelectedObjects]

    if { $lSelObjs == "" || $lSelObjs == $lNullObj } {
        puts "NCC Plugin: No component selected."
        return
    }

    set lPropNameCS  [DboTclHelper_sMakeCString $PROP_NAME]
    set lPropValueCS [DboTclHelper_sMakeCString $PROP_VALUE]
    set lValueNameCS [DboTclHelper_sMakeCString "Value"]

    foreach lObj $lSelObjs {
        catch { DboPlacedInst -this $lObj }

        set lSetStatus [$lObj SetEffectivePropStringValue $lPropNameCS $lPropValueCS]
        if { [$lSetStatus OK] != 1 } {
            incr lErrCount
            continue
        }

        $lObj SetColor $GREY_COLOR

        set lValueDisp [$lObj GetDisplayProp $lValueNameCS $lStatus]
        if { $lValueDisp != $lNullObj } {
            DboDisplayProp -this $lValueDisp
            $lValueDisp SetColor $GREY_COLOR
        }

        set lDispProp [$lObj GetDisplayProp $lPropNameCS $lStatus]

        if { $lDispProp == $lNullObj } {
            set lPropLoc [DboTclHelper_sMakeCPoint 10 40]
            set lLogFont [DboTclHelper_sMakeLOGFONT]
            set lRotation 0

            set lDispProp [$lObj NewDisplayProp \
                $lStatus $lPropNameCS $lPropLoc $lRotation $lLogFont $GREY_COLOR]
        }

        if { $lDispProp != $lNullObj } {
            DboDisplayProp -this $lDispProp
            if { [$lDispProp GetDisplayType $lStatus] != 1 } {
                $lDispProp SetDisplayType 1
            }
            $lDispProp SetColor $GREY_COLOR
        }

        incr lCount
    }

    DboTclHelper_sDeleteCString $lPropNameCS
    DboTclHelper_sDeleteCString $lPropValueCS
    DboTclHelper_sDeleteCString $lValueNameCS
    $lStatus -delete

    if { $lCount > 0 } {
        puts "NCC Plugin: Marked $lCount component(s) as NC (grey)."
    }
    if { $lErrCount > 0 } {
        puts "NCC Plugin: $lErrCount component(s) failed."
    }
}

proc capNCCProperty_register {} {
    RegisterAction "_cdnCapActionNCCProperty" "capNCCProperty_shouldProcess" "" "capNCCProperty_execute" ""
    RegisterAction "_cdnCapUpdateNCCProperty" "capNCCProperty_shouldProcess" "" "capNCCProperty_enable" ""
    RegisterAction "AddNCCPropertyHotkey" "capTrue" "Ctrl+Q" "capNCCProperty_execute" "Schematic"
    InsertXMLMenu [list [list "Tools" "ToolsAddNCCProperty"] "" "" [list "action" "Add NCC &Property" "0" "_cdnCapActionNCCProperty" "_cdnCapUpdateNCCProperty" "" "" "" "Add NCC=NC property, display NC, grey part (Ctrl+Q)"] ""]
}

capNCCProperty_register
