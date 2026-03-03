#############################################################################
# capPublishDesign.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Publish Design (Normal)
# @Version:      1.1.0
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

    # ------------------------------------------------------------------
    # Step 0: Get active design
    # ------------------------------------------------------------------
    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == "NULL"} {
        puts "Publish Design: ERROR - No active design."
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
        puts "Publish Design: ERROR - Cannot get root schematic."
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
    # Step 3: Resolve the DSN file path
    # ------------------------------------------------------------------
    set lDsnPath [file normalize $lDesignPath]
    set lDesignDir [file dirname $lDsnPath]
    set lExt [file extension $lDsnPath]

    # GetName may return the .DSN directly or the .opj
    if {[string tolower $lExt] == ".dsn"} {
        set lDsnFile $lDsnPath
        set lBaseName [file rootname [file tail $lDsnPath]]
    } else {
        # It's an .opj — look for a .dsn with the same base name
        set lBaseName [file rootname [file tail $lDsnPath]]
        set lDsnFile [file join $lDesignDir "${lBaseName}.dsn"]
        if {![file exists $lDsnFile]} {
            set lDsnFiles [glob -nocomplain -directory $lDesignDir *.dsn]
            if {[llength $lDsnFiles] == 0} {
                puts "Publish Design: ERROR - Cannot find .dsn file."
                return
            }
            set lDsnFile [lindex $lDsnFiles 0]
            set lBaseName [file rootname [file tail $lDsnFile]]
        }
    }

    set lTimestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set lNewFileName "${lBaseName}_${lTimestamp}.dsn"

    puts "Publish Design: Source DSN = $lDsnFile"
    puts "Publish Design: New filename = $lNewFileName"

    # ------------------------------------------------------------------
    # Step 4: Prompt user to choose save directory
    # ------------------------------------------------------------------
    # Use Capture built-in directory chooser (capOpenArchiveDialog)
    # Fall back to tk_chooseDirectory if capOpenArchiveDialog is unavailable
    set lSaveDir ""
    if {[catch {
        set lInitDir [DboTclHelper_sMakeCString $lDesignDir]
        set lChosenPath [capOpenArchiveDialog $lInitDir]
        set lSaveDir [DboTclHelper_sGetConstCharPtr $lChosenPath]
    } errMsg]} {
        puts "Publish Design: capOpenArchiveDialog failed ($errMsg), trying tk_chooseDirectory..."
        if {[catch {
            set lSaveDir [tk_chooseDirectory \
                -title "发布原理图 - 选择保存目录 (Publish Design)" \
                -initialdir $lDesignDir]
        } errMsg2]} {
            puts "Publish Design: tk_chooseDirectory also failed ($errMsg2)."
            set lSaveDir ""
        }
    }

    if {$lSaveDir == ""} {
        puts "Publish Design: User cancelled or dialog failed."
        return
    }

    set lSavePath [file join $lSaveDir $lNewFileName]

    puts "Publish Design: Saving to $lSavePath"

    # ------------------------------------------------------------------
    # Step 5: Copy DSN file to user-chosen location
    # ------------------------------------------------------------------
    if {[catch {file copy -force $lDsnFile $lSavePath} errMsg]} {
        puts "Publish Design: ERROR - Save failed: $errMsg"
        return
    }

    puts "Publish Design: SUCCESS - Saved to $lSavePath"
    puts "Publish Design: NC components processed: $lNCCount"
}

proc capPublishDesign_register {} {
    RegisterAction "_cdnCapActionPublishDesign" "capPublishDesign_shouldProcess" "" "capPublishDesign_execute" ""
    RegisterAction "_cdnCapUpdatePublishDesign" "capPublishDesign_shouldProcess" "" "capPublishDesign_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsPublishDesign"] "" "" [list "action" "Publish &Design" "0" "_cdnCapActionPublishDesign" "_cdnCapUpdatePublishDesign" "" "" "" "Publish design: process NC parts and save DSN with timestamp"] ""]
}

capPublishDesign_register
