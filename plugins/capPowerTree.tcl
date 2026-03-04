#############################################################################
# capPowerTree.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Power Tree Extractor
# @Version:      1.0.0
# @Author:       KAIDOU.WU
# @Menu:         Tools > Export Power Tree
# @Description:  提取所有电源网络拓扑数据，导出JSON文件用于分析
#############################################################################

proc capPowerTree_shouldProcess {args} {
    return true
}

proc capPowerTree_enable {args} {
    return true
}

# =========================================================================
# Helper: Classify pin type enum to string
# =========================================================================
proc capPowerTree_pinTypeStr {ptype} {
    if {$ptype == $::POWER}   { return "POWER"   }
    if {$ptype == $::DBO_IN}  { return "INPUT"   }
    if {$ptype == $::DBO_OUT} { return "OUTPUT"  }
    if {$ptype == $::IO}      { return "BIDIR"   }
    if {$ptype == $::PAS}     { return "PASSIVE" }
    if {$ptype == $::HIZ}     { return "HIGH_Z"  }
    if {$ptype == $::OC}      { return "OPEN_COLLECTOR" }
    if {$ptype == $::OE}      { return "OPEN_EMITTER"   }
    return "UNKNOWN"
}

# =========================================================================
# Helper: Escape string for JSON output
# =========================================================================
proc capPowerTree_jsonEscape {str} {
    set str [string map {\\ \\\\ \" \\\" \n \\n \r \\r \t \\t} $str]
    return $str
}

# =========================================================================
# Helper: Classify component role based on Part Name / Value
# =========================================================================
proc capPowerTree_classifyComponent {partName value refdes} {
    set pn [string toupper $partName]
    set val [string toupper $value]
    set ref [string toupper $refdes]

    # Combined search string: check both partName and value
    # (some designs store part number in Value field)
    set search "$pn $val"

    # LDO regulators (match common LDO part numbers)
    if {[regexp {LDO|AMS1117|HT73|ME6211|RT9013|AP2112|MIC5504|TLV70|TPS7A|LP2985|LP5907|NCV8|SPX3819|XC6206|XC6220|ETA5055|SGM2019|SGM2036|LP5907|NCP16|MCP1700|AP7370|AP7380} $search]} {
        return "LDO"
    }
    # DC-DC converters
    if {[regexp {DCDC|DC-DC|TPS5|TPS6|LM25|LM26|MP1|MP2|SY8|RT7|RT8|AOZ|NCP|LMR|TLV6|AP63|AP64|SIC4|MT2|MT3|XL|ETA2865|ETA3425|SGM6603|SYR8|TPS54|TPS62|LM267|MPQ} $search]} {
        return "DCDC"
    }
    # MOSFET / power transistors
    if {[regexp {^Q} $ref] && [regexp {MOS|FET|NMOS|PMOS|CJ[ABCD]} $search]} {
        return "MOSFET"
    }
    if {[regexp {CJAB|CJAC|AO34|SI23|BSS138|2N7002|IRLML} $search]} {
        return "MOSFET"
    }
    # Voltage references
    if {[regexp {VREF|LM4040|TL431|ADR} $search]} {
        return "VREF"
    }
    # Power switches / load switches
    if {[regexp {SWITCH|TPS22|SIP3|RT9742|AP22} $search]} {
        return "SWITCH"
    }
    # Level translators
    if {[regexp {ETA4553|TXB0|TXS0|GTL2002|SN74|LSF0|NVT20} $search]} {
        return "LEVEL_SHIFTER"
    }
    # Ferrite beads (by value pattern: xxxR-xxxMHz or refdes FB*)
    if {[regexp {^FB} $ref]} {
        return "FERRITE_BEAD"
    }
    if {[regexp {^L} $ref] && [regexp {R.*MHZ} $val]} {
        return "FERRITE_BEAD"
    }
    # Inductors (by refdes L* and value like xxuH)
    if {[regexp {^L} $ref]} {
        return "INDUCTOR"
    }
    # Capacitors
    if {[regexp {^C} $ref]} {
        return "CAP"
    }
    # Resistors
    if {[regexp {^R} $ref]} {
        return "RES"
    }
    # Diodes
    if {[regexp {^D} $ref]} {
        return "DIODE"
    }
    # Connectors
    if {[regexp {^J|^P[0-9]|^CN|CONN} $ref]} {
        return "CONNECTOR"
    }
    # Test points
    if {[regexp {^TP} $ref]} {
        return "TEST_POINT"
    }
    # Crystals / oscillators
    if {[regexp {^X|^Y} $ref]} {
        return "CRYSTAL"
    }
    # Switches
    if {[regexp {^S[0-9]} $ref]} {
        return "SWITCH_MECH"
    }
    # ICs (generic fallback for U*)
    if {[regexp {^U} $ref]} {
        return "IC"
    }

    return "OTHER"
}

# =========================================================================
# Helper: Check if a net name matches power/ground naming patterns
#
# Strategy: Only match nets whose name clearly IS a power rail.
# Nets like "UWB_SWDIO_1V8" have a voltage suffix but are signals
# in a voltage domain — NOT power rails. We avoid matching those.
# =========================================================================
proc capPowerTree_isPowerNet {netName} {
    set n [string toupper $netName]

    # Skip auto-generated unnamed nets (N followed by digits)
    if {[regexp {^N\d+$} $netName]} {
        return 0
    }

    # ── Explicit power rail prefixes ──────────────────────────────
    # VCC_*, VDD_*, VBUS, VOUT, VBAT, VSYS, VREF, VIN, V+, V-
    if {[regexp {^V(CC|DD|BUS|OUT|BAT|SYS|REF|IN)($|[_0-9])} $n]} { return 1 }
    if {[regexp {^V[+-]} $n]} { return 1 }

    # Bare voltage rails: +3V3, +5V, +1V8, 3.3V, 12V, etc.
    if {[regexp {^\+?[0-9]+\.?[0-9]*V[0-9]*$} $n]} { return 1 }

    # ── Ground patterns ───────────────────────────────────────────
    # GND, GND_SIGNAL, AGND, DGND, PGND, etc.
    # Must START with GND or be exactly *GND (AGND, DGND, PGND)
    if {[regexp {^GND($|_)} $n]}  { return 1 }
    if {[regexp {^[ADP]GND($|_)} $n]} { return 1 }

    # ── Power keywords anywhere (but NOT as suffix of signal names) ──
    # Only match if the net contains VCC/VDD as a word boundary
    # e.g. "VCC_USB_VBUS" yes, "UWB_SWDIO_1V8" no
    if {[regexp {(^|_)(VCC|VDD|VBUS|VBAT|VSYS)($|_)} $n]} { return 1 }

    return 0
}

# =========================================================================
# Main: Extract power tree topology
# =========================================================================
proc capPowerTree_execute {} {

    set lNullObj "NULL"

    # ------------------------------------------------------------------
    # Step 0: Get active design
    # ------------------------------------------------------------------
    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == $lNullObj} {
        puts "Power Tree: ERROR - No active design."
        return
    }

    set lDesignName [DboTclHelper_sMakeCString]
    $objDesign GetName $lDesignName
    set lDesignPath [DboTclHelper_sGetConstCharPtr $lDesignName]

    puts "Power Tree: Design = $lDesignPath"
    puts "Power Tree: Scanning all flat nets..."

    # ------------------------------------------------------------------
    # Step 1: Iterate all flat nets, collect power net data
    # ------------------------------------------------------------------
    set lStatus [DboState]

    set netIter [$objDesign NewFlatNetsIter $lStatus]
    if {$netIter == $lNullObj || $netIter == ""} {
        puts "Power Tree: ERROR - Cannot create flat net iterator."
        return
    }

    # Data structures:
    #   powerNets: dict  netName -> list of pin records
    #   components: dict  refdes -> {partName value role}
    #   allNetCount: total nets scanned
    #   powerNetCount: power nets found

    set powerNets [dict create]
    set components [dict create]
    set allNetCount 0
    set powerNetCount 0

    set net [$netIter NextFlatNet $lStatus]
    while {$net != $lNullObj && $net != ""} {

        incr allNetCount

        # Get net name
        set netNameCS [DboTclHelper_sMakeCString]
        $net GetName $netNameCS
        set netName [DboTclHelper_sGetConstCharPtr $netNameCS]

        # Check if this is a power net by name pattern
        set isPower [capPowerTree_isPowerNet $netName]

        # Iterate all pin occurrences on this net
        set pinIter [$net NewPortOccurrencesIter $lStatus]
        set pinList {}
        set pinCount 0

        if {$pinIter != $lNullObj && $pinIter != ""} {

            set pin [$pinIter NextPortOccurrence $lStatus]
            while {$pin != $lNullObj && $pin != ""} {

                incr pinCount

                # Get port instance
                set pinInst [$pin GetPortInst $lStatus]

                if {$pinInst != $lNullObj && $pinInst != ""} {

                    # Pin type
                    set ptype [$pinInst GetPinType $lStatus]
                    set ptypeStr [capPowerTree_pinTypeStr $ptype]

                    # Pin number
                    set pinNumCS [DboTclHelper_sMakeCString]
                    $pinInst GetPinNumber $pinNumCS
                    set pinNum [DboTclHelper_sGetConstCharPtr $pinNumCS]

                    # Pin name
                    set pinNameCS [DboTclHelper_sMakeCString]
                    $pinInst GetPinName $pinNameCS
                    set pinName [DboTclHelper_sGetConstCharPtr $pinNameCS]

                    # Owner component — get RefDes, Part Name, Value
                    set lOwner [$pinInst GetOwner]
                    set refdes ""
                    set partName ""
                    set partValue ""

                    if {$lOwner != $lNullObj && $lOwner != ""} {
                        set lPropRef [DboTclHelper_sMakeCString "Part Reference"]
                        set lPropVal [DboTclHelper_sMakeCString]
                        set lGetSt [$lOwner GetEffectivePropStringValue $lPropRef $lPropVal]
                        if {[$lGetSt OK] == 1} {
                            set refdes [DboTclHelper_sGetConstCharPtr $lPropVal]
                        }

                        set lPropPN [DboTclHelper_sMakeCString "Part Name"]
                        set lPNVal  [DboTclHelper_sMakeCString]
                        set lGetSt2 [$lOwner GetEffectivePropStringValue $lPropPN $lPNVal]
                        if {[$lGetSt2 OK] == 1} {
                            set partName [DboTclHelper_sGetConstCharPtr $lPNVal]
                        }

                        set lPropV  [DboTclHelper_sMakeCString "Value"]
                        set lVVal   [DboTclHelper_sMakeCString]
                        set lGetSt3 [$lOwner GetEffectivePropStringValue $lPropV $lVVal]
                        if {[$lGetSt3 OK] == 1} {
                            set partValue [DboTclHelper_sGetConstCharPtr $lVVal]
                        }
                    }

                    # Classify component role
                    set role [capPowerTree_classifyComponent $partName $partValue $refdes]

                    # Store pin record
                    lappend pinList [list $refdes $pinNum $pinName $ptypeStr $partName $partValue $role]

                    # Track unique components
                    if {$refdes != "" && ![dict exists $components $refdes]} {
                        dict set components $refdes [list $partName $partValue $role]
                    }
                }

                set pin [$pinIter NextPortOccurrence $lStatus]
            }
            delete_DboFlatNetPortOccurrencesIter $pinIter
        }

        # Power net identified by name pattern
        if {$isPower && $pinCount > 0} {
            dict set powerNets $netName $pinList
            incr powerNetCount
        }

        set net [$netIter NextFlatNet $lStatus]
    }
    delete_DboDesignFlatNetsIter $netIter

    puts "Power Tree: Scanned $allNetCount nets, found $powerNetCount power nets."
    puts "Power Tree: Found [dict size $components] unique components on power nets."

    if {$powerNetCount == 0} {
        puts "Power Tree: WARNING - No power nets found. Check net naming conventions."
        return
    }

    # ------------------------------------------------------------------
    # Step 2: Ask user where to save
    # ------------------------------------------------------------------
    set lDesignDir [file dirname [file normalize $lDesignPath]]
    set lTimestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set lJsonFileName "power_tree_${lTimestamp}.json"

    set lSaveDir ""
    if {[catch {
        set lInitDir [DboTclHelper_sMakeCString $lDesignDir]
        set lChosenPath [capOpenArchiveDialog $lInitDir]
        set lSaveDir [DboTclHelper_sGetConstCharPtr $lChosenPath]
    } errMsg]} {
        puts "Power Tree: capOpenArchiveDialog failed ($errMsg), trying tk_chooseDirectory..."
        if {[catch {
            set lSaveDir [tk_chooseDirectory \
                -title "导出电源树 - 选择保存目录 (Export Power Tree)" \
                -initialdir $lDesignDir]
        } errMsg2]} {
            puts "Power Tree: tk_chooseDirectory also failed ($errMsg2)."
            set lSaveDir ""
        }
    }

    if {$lSaveDir == ""} {
        puts "Power Tree: User cancelled or dialog failed."
        return
    }

    set lJsonPath [file join $lSaveDir $lJsonFileName]

    # ------------------------------------------------------------------
    # Step 3: Build summary statistics
    # ------------------------------------------------------------------
    # Count components by role
    set roleCounts [dict create]
    dict for {ref info} $components {
        set role [lindex $info 2]
        if {[dict exists $roleCounts $role]} {
            dict set roleCounts $role [expr {[dict get $roleCounts $role] + 1}]
        } else {
            dict set roleCounts $role 1
        }
    }

    # ------------------------------------------------------------------
    # Step 4: Write JSON output
    # ------------------------------------------------------------------
    set fh [open $lJsonPath w]
    fconfigure $fh -encoding utf-8

    puts $fh "\{"
    puts $fh "  \"design\": \"[capPowerTree_jsonEscape [file tail $lDesignPath]]\","
    puts $fh "  \"exportTime\": \"[clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]\","
    puts $fh "  \"totalNets\": $allNetCount,"
    puts $fh "  \"powerNetCount\": $powerNetCount,"
    puts $fh "  \"componentCount\": [dict size $components],"

    # -- Summary by role --
    puts $fh "  \"componentSummary\": \{"
    set rfirst 1
    dict for {role cnt} $roleCounts {
        if {!$rfirst} { puts $fh "," }
        set rfirst 0
        puts -nonewline $fh "    \"[capPowerTree_jsonEscape $role]\": $cnt"
    }
    puts $fh ""
    puts $fh "  \},"

    # -- Components dict --
    puts $fh "  \"components\": \{"
    set cfirst 1
    dict for {ref info} $components {
        if {!$cfirst} { puts $fh "," }
        set cfirst 0
        set pn  [capPowerTree_jsonEscape [lindex $info 0]]
        set pv  [capPowerTree_jsonEscape [lindex $info 1]]
        set rl  [capPowerTree_jsonEscape [lindex $info 2]]
        puts -nonewline $fh "    \"[capPowerTree_jsonEscape $ref]\": \{\"partName\": \"$pn\", \"value\": \"$pv\", \"role\": \"$rl\"\}"
    }
    puts $fh ""
    puts $fh "  \},"

    # -- Power nets with pin details --
    puts $fh "  \"powerNets\": \{"
    set nfirst 1
    dict for {netName pins} $powerNets {
        if {!$nfirst} { puts $fh "," }
        set nfirst 0
        puts $fh "    \"[capPowerTree_jsonEscape $netName]\": \["
        set pfirst 1
        foreach p $pins {
            if {!$pfirst} { puts $fh "," }
            set pfirst 0
            set ref     [capPowerTree_jsonEscape [lindex $p 0]]
            set pinNum  [capPowerTree_jsonEscape [lindex $p 1]]
            set pinName [capPowerTree_jsonEscape [lindex $p 2]]
            set pinType [capPowerTree_jsonEscape [lindex $p 3]]
            set pn      [capPowerTree_jsonEscape [lindex $p 4]]
            set pv      [capPowerTree_jsonEscape [lindex $p 5]]
            set rl      [capPowerTree_jsonEscape [lindex $p 6]]
            puts -nonewline $fh "      \{\"ref\": \"$ref\", \"pin\": \"$pinNum\", \"pinName\": \"$pinName\", \"pinType\": \"$pinType\", \"partName\": \"$pn\", \"value\": \"$pv\", \"role\": \"$rl\"\}"
        }
        puts $fh ""
        puts $fh "    \]"
    }
    puts $fh ""
    puts $fh "  \}"

    puts $fh "\}"
    close $fh

    # ------------------------------------------------------------------
    # Step 5: Print summary to console
    # ------------------------------------------------------------------
    puts "Power Tree: ================================================"
    puts "Power Tree: Export complete!"
    puts "Power Tree: File: $lJsonPath"
    puts "Power Tree: Power nets: $powerNetCount"
    puts "Power Tree: Components on power nets: [dict size $components]"
    puts "Power Tree: ------------------------------------------------"
    dict for {role cnt} $roleCounts {
        puts "Power Tree:   $role: $cnt"
    }
    puts "Power Tree: ================================================"

    # Also print a quick text summary of power net connections
    puts ""
    puts "Power Tree: === Power Net Summary ==="
    dict for {netName pins} $powerNets {
        set connList {}
        foreach p $pins {
            set ref  [lindex $p 0]
            set pNum [lindex $p 1]
            set pNm  [lindex $p 2]
            set pTyp [lindex $p 3]
            if {$ref != ""} {
                lappend connList "${ref}.${pNm}(${pTyp})"
            }
        }
        puts "  $netName: [join $connList { -> }]"
    }
    puts "Power Tree: === End ==="
}

# =========================================================================
# Registration: Menu entry under Tools
# =========================================================================
proc capPowerTree_register {} {
    RegisterAction "_cdnCapActionPowerTree" "capPowerTree_shouldProcess" "" "capPowerTree_execute" ""
    RegisterAction "_cdnCapUpdatePowerTree" "capPowerTree_shouldProcess" "" "capPowerTree_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsExportPowerTree"] "" "" [list "action" "Export Power &Tree" "0" "_cdnCapActionPowerTree" "_cdnCapUpdatePowerTree" "" "" "" "Export power network topology to JSON for analysis"] ""]
}

capPowerTree_register
