#############################################################################
# capPublishDesign.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Publish Design (Normal)
# @Version:      1.0.0
# @Author:       KAIDOU.WU
# @Menu:         Tools > Publish Design
# @Description:  自动处理NCC=NC器件(变灰+显示NC)，另存DSN文件加时间戳
#############################################################################

proc capPublishDesign_shouldProcess {args} {
    return true
}

proc capPublishDesign_enable {args} {
    return true
}

proc capPublishDesign_execute {} {

    set PROP_NAME  "NCC"
    set PROP_VALUE "NC"
    set GREY_COLOR  45
    set DEFAULT_COLOR 48

    # ------------------------------------------------------------------
    # Step 0: Get active design
    # ------------------------------------------------------------------
    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == "NULL"} {
        tk_messageBox -icon error -title "Publish Design" \
            -message "没有打开的设计文件。\nNo active design."
        return
    }

    set lDesignName [DboTclHelper_sMakeCString]
    $objDesign GetName $lDesignName
    set lDesignPath [DboTclHelper_sGetConstCharPtr $lDesignName]

    puts "Publish Design: Design path = $lDesignPath"

    # ------------------------------------------------------------------
    # Step 1: Scan all pages, process NCC=NC components
    # ------------------------------------------------------------------
    set lStatus [DboState]
    set objSchematic [$objDesign GetRootSchematic $lStatus]
    if {$objSchematic == "" || $objSchematic == "NULL"} {
        tk_messageBox -icon error -title "Publish Design" \
            -message "无法获取原理图。\nCannot get root schematic."
        return
    }

    set lPropNameCS  [DboTclHelper_sMakeCString $PROP_NAME]
    set lPropValueCS [DboTclHelper_sMakeCString ""]
    set lValueNameCS [DboTclHelper_sMakeCString "Value"]

    set lNullObj "NULL"
    set lTotalCount 0
    set lNCCount 0

    set lStatus2 [DboState]
    set objPageIter [$objSchematic NewPagesIter $lStatus2]
    set lStatus3 [DboState]
    set objPage [$objPageIter NextPage $lStatus3]

    while {$objPage != $lNullObj && $objPage != ""} {

        set lStatus4 [DboState]
        set objInstIter [$objPage NewPartInstsIter $lStatus4]
        set lStatus5 [DboState]
        set objInst [$objInstIter NextPartInst $lStatus5]

        while {$objInst != $lNullObj && $objInst != ""} {
            incr lTotalCount

            # Read NCC property value
            set lReadVal [DboTclHelper_sMakeCString ""]
            set lGetStatus [$objInst GetEffectivePropStringValue $lPropNameCS $lReadVal]

            if {[$lGetStatus OK] == 1} {
                set lVal [DboTclHelper_sGetConstCharPtr $lReadVal]

                if {$lVal == $PROP_VALUE} {
                    # This component has NCC=NC -> grey it + ensure NC display
                    incr lNCCount

                    # Set component grey
                    $objInst SetColor $GREY_COLOR

                    # Grey the Value display prop if exists
                    set lValDisp [$objInst GetDisplayProp $lValueNameCS $lStatus]
                    if {$lValDisp != $lNullObj} {
                        DboDisplayProp -this $lValDisp
                        $lValDisp SetColor $GREY_COLOR
                    }

                    # Ensure NCC display prop exists and shows value
                    set lDispProp [$objInst GetDisplayProp $lPropNameCS $lStatus]
                    if {$lDispProp == $lNullObj} {
                        set lPropLoc [DboTclHelper_sMakeCPoint 10 40]
                        set lLogFont [DboTclHelper_sMakeLOGFONT]
                        set lRotation 0
                        set lDispProp [$objInst NewDisplayProp \
                            $lStatus $lPropNameCS $lPropLoc $lRotation $lLogFont $GREY_COLOR]
                    }
                    if {$lDispProp != $lNullObj} {
                        DboDisplayProp -this $lDispProp
                        if {[$lDispProp GetDisplayType $lStatus] != 1} {
                            $lDispProp SetDisplayType 1
                        }
                        $lDispProp SetColor $GREY_COLOR
                    }
                }
            }

            set lStatus5 [DboState]
            set objInst [$objInstIter NextPartInst $lStatus5]
        }

        set lStatus3 [DboState]
        set objPage [$objPageIter NextPage $lStatus3]
    }

    DboTclHelper_sDeleteCString $lPropNameCS
    DboTclHelper_sDeleteCString $lValueNameCS
    $lStatus -delete

    puts "Publish Design: Scanned $lTotalCount components, $lNCCount marked as NC (grey)."

    # ------------------------------------------------------------------
    # Step 2: Save current design first
    # ------------------------------------------------------------------
    catch {Menu "File::Save"}

    # ------------------------------------------------------------------
    # Step 3: Build timestamped filename and prompt user for save location
    # ------------------------------------------------------------------
    set lDsnPath [file normalize $lDesignPath]

    # Find the .dsn file(s) in the design directory
    # The design path is the .opj file, the .dsn is in the same directory
    set lDesignDir [file dirname $lDsnPath]
    set lBaseName [file rootname [file tail $lDsnPath]]
    set lTimestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set lNewBaseName "${lBaseName}_${lTimestamp}"

    # Find corresponding .dsn file
    set lDsnFile [file join $lDesignDir "${lBaseName}.dsn"]
    if {![file exists $lDsnFile]} {
        # Try to find any .dsn in the directory
        set lDsnFiles [glob -nocomplain -directory $lDesignDir *.dsn]
        if {[llength $lDsnFiles] == 0} {
            tk_messageBox -icon error -title "Publish Design" \
                -message "找不到 .dsn 文件。\nCannot find .dsn file in design directory."
            return
        }
        set lDsnFile [lindex $lDsnFiles 0]
        set lBaseName [file rootname [file tail $lDsnFile]]
        set lNewBaseName "${lBaseName}_${lTimestamp}"
    }

    set lDefaultSaveName "${lNewBaseName}.dsn"

    # Use Tk save dialog
    set lSavePath [tk_getSaveFile \
        -title "发布原理图 - 选择保存位置 (Publish Design)" \
        -initialdir $lDesignDir \
        -initialfile $lDefaultSaveName \
        -defaultextension ".dsn" \
        -filetypes {{"OrCAD Schematic" {.dsn}} {"All Files" {*}}}]

    if {$lSavePath == ""} {
        puts "Publish Design: User cancelled save."
        return
    }

    # ------------------------------------------------------------------
    # Step 4: Copy DSN file to user-chosen location
    # ------------------------------------------------------------------
    if {[catch {file copy -force $lDsnFile $lSavePath} errMsg]} {
        tk_messageBox -icon error -title "Publish Design" \
            -message "保存失败: $errMsg\nFailed to save: $errMsg"
        return
    }

    set lNCMsg ""
    if {$lNCCount > 0} {
        set lNCMsg "\n已处理 $lNCCount 个NC器件 (变灰+显示NC)"
    }

    tk_messageBox -icon info -title "Publish Design" \
        -message "发布成功！$lNCMsg\n\n保存至:\n$lSavePath"

    puts "Publish Design: Successfully saved to $lSavePath"
}

proc capPublishDesign_register {} {
    RegisterAction "_cdnCapActionPublishDesign" "capPublishDesign_shouldProcess" "" "capPublishDesign_execute" ""
    RegisterAction "_cdnCapUpdatePublishDesign" "capPublishDesign_shouldProcess" "" "capPublishDesign_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsPublishDesign"] "" "" [list "action" "Publish &Design" "0" "_cdnCapActionPublishDesign" "_cdnCapUpdatePublishDesign" "" "" "" "Publish design: process NC parts and save DSN with timestamp"] ""]
}

capPublishDesign_register
