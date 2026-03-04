#############################################################################
# capNetAudit.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Net Name Audit
# @Version:      1.0.0
# @Author:       KAIDOU.WU
# @Menu:         Tools > Net Name Audit
# @Description:  扫描全设计网络名,检测相似/可疑命名(拼写差异,大小写,尾缀混淆等)
#############################################################################

proc capNetAudit_shouldProcess {args} {
    return true
}

proc capNetAudit_enable {args} {
    return true
}

# ======================================================================
# Levenshtein distance — pure TCL implementation
# Returns edit distance between two strings
# ======================================================================
proc capNetAudit_levenshtein {s t} {
    set m [string length $s]
    set n [string length $t]

    if {$m == 0} { return $n }
    if {$n == 0} { return $m }

    # Init row
    for {set j 0} {$j <= $n} {incr j} {
        set prev($j) $j
    }

    for {set i 1} {$i <= $m} {incr i} {
        set curr(0) $i
        for {set j 1} {$j <= $n} {incr j} {
            set ci [string index $s [expr {$i - 1}]]
            set cj [string index $t [expr {$j - 1}]]
            if {$ci == $cj} {
                set cost 0
            } else {
                set cost 1
            }
            set del   [expr {$prev($j) + 1}]
            set ins   [expr {$curr([expr {$j - 1}]) + 1}]
            set sub   [expr {$prev([expr {$j - 1}]) + $cost}]
            set mn $del
            if {$ins < $mn} { set mn $ins }
            if {$sub < $mn} { set mn $sub }
            set curr($j) $mn
        }
        for {set j 0} {$j <= $n} {incr j} {
            set prev($j) $curr($j)
        }
    }
    return $prev($n)
}

# ======================================================================
# Normalize net name for grouping:
# Strip trailing digits, underscores, suffixes to find the "base" name
# e.g. VCC_3V3 -> VCC, VBUS1 -> VBUS, SDA_0 -> SDA
# ======================================================================
proc capNetAudit_baseName {name} {
    set upper [string toupper $name]
    # Strip trailing _digits or pure trailing digits
    regsub {[_]?\d+$} $upper {} base
    # Strip trailing _xVy voltage suffixes like _3V3, _1V8
    regsub {[_]?\d+V\d+$} $base {} base2
    if {$base2 != ""} { return $base2 }
    if {$base != ""}  { return $base  }
    return $upper
}

# ======================================================================
# Check if two net names are "suspiciously similar"
# Returns: 0=no issue, 1=case-only diff, 2=close edit distance,
#          3=same base different suffix, 4=underscore variant
# ======================================================================
proc capNetAudit_checkSimilar {name1 name2} {
    if {$name1 == $name2} { return 0 }

    set u1 [string toupper $name1]
    set u2 [string toupper $name2]

    # Case-only difference (VCC vs Vcc vs vcc)
    if {$u1 == $u2} { return 1 }

    # Underscore variant (VCC3V3 vs VCC_3V3)
    set n1 [string map {"_" ""} $u1]
    set n2 [string map {"_" ""} $u2]
    if {$n1 == $n2} { return 4 }

    # Same base, different suffix (VCC_3V3 vs VCC_1V8 — these are OK,
    # but VCC vs VCC1 or VBUS vs VBUS2 with only 1 char diff is suspicious)
    set b1 [capNetAudit_baseName $name1]
    set b2 [capNetAudit_baseName $name2]

    # Short names: only flag if base is identical AND total length very close
    set len1 [string length $u1]
    set len2 [string length $u2]
    set lenDiff [expr {abs($len1 - $len2)}]

    if {$b1 == $b2 && $lenDiff <= 1 && $len1 <= 8} {
        return 3
    }

    # Levenshtein: flag if edit distance is 1 AND names are at least 3 chars
    if {$len1 >= 3 && $len2 >= 3} {
        set dist [capNetAudit_levenshtein $u1 $u2]
        if {$dist == 1} { return 2 }
    }

    return 0
}

# ======================================================================
# Describe similarity type
# ======================================================================
proc capNetAudit_descSimilar {code} {
    switch $code {
        1 { return "Case diff only" }
        2 { return "Edit dist = 1" }
        3 { return "Same base" }
        4 { return "Underscore variant" }
        default { return "Unknown" }
    }
}

# ======================================================================
# Main execute: collect all nets, find similar pairs, show report
# ======================================================================
proc capNetAudit_execute {} {

    set lNullObj "NULL"

    # ------------------------------------------------------------------
    # Step 1: Get active design
    # ------------------------------------------------------------------
    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == $lNullObj} {
        puts "Net Audit: ERROR - No active design."
        return
    }

    puts "Net Audit: Collecting all net names..."

    # ------------------------------------------------------------------
    # Step 2: Collect all flat net names
    # ------------------------------------------------------------------
    set allNets {}
    set lStatus [DboState]

    set lNetIter [$objDesign NewFlatNetsIter $lStatus]
    set lFlatNet [$lNetIter NextFlatNet $lStatus]

    while {$lFlatNet != $lNullObj} {
        set lNameCS [DboTclHelper_sMakeCString]
        $lFlatNet GetName $lNameCS
        set lNetName [DboTclHelper_sGetConstCharPtr $lNameCS]

        if {$lNetName != ""} {
            lappend allNets $lNetName
        }

        set lFlatNet [$lNetIter NextFlatNet $lStatus]
    }
    delete_DboDesignFlatNetsIter $lNetIter
    $lStatus -delete

    set netCount [llength $allNets]
    puts "Net Audit: Found $netCount nets."

    if {$netCount == 0} {
        puts "Net Audit: No nets found."
        return
    }

    # ------------------------------------------------------------------
    # Step 3: Filter out auto-generated net names (N00123, N12345 etc.)
    # These are unnamed wires, not worth comparing
    # ------------------------------------------------------------------
    set namedNets {}
    set autoCount 0
    foreach n $allNets {
        if {[regexp {^N\d{4,}$} $n]} {
            incr autoCount
        } else {
            lappend namedNets $n
        }
    }
    set namedCount [llength $namedNets]
    puts "Net Audit: $namedCount named nets ($autoCount auto-generated skipped)."

    # ------------------------------------------------------------------
    # Step 4: Also collect per-page globals (power symbols) as supplementary
    # ------------------------------------------------------------------
    set lStatus2 [DboState]
    set objSchematic [$objDesign GetRootSchematic $lStatus2]
    set globalNets {}

    if {$objSchematic != "" && $objSchematic != $lNullObj} {
        set lPageIter [$objSchematic NewPagesIter $lStatus2]
        set lPage [$lPageIter NextPage $lStatus2]

        while {$lPage != $lNullObj && $lPage != ""} {
            set lGlobIter [$lPage NewGlobalsIter $lStatus2]
            set lGlobal [$lGlobIter NextGlobal $lStatus2]

            while {$lGlobal != $lNullObj} {
                set lGNameCS [DboTclHelper_sMakeCString]
                $lGlobal GetName $lGNameCS
                set gName [DboTclHelper_sGetConstCharPtr $lGNameCS]
                if {$gName != ""} {
                    lappend globalNets $gName
                }
                set lGlobal [$lGlobIter NextGlobal $lStatus2]
            }

            set lPage [$lPageIter NextPage $lStatus2]
        }
    }
    $lStatus2 -delete

    # Merge globals into named nets (deduplicate)
    foreach g $globalNets {
        if {[lsearch -exact $namedNets $g] == -1} {
            lappend namedNets $g
        }
    }
    set namedCount [llength $namedNets]

    # ------------------------------------------------------------------
    # Step 5: Find all suspicious pairs (O(n^2) but n is small for nets)
    # ------------------------------------------------------------------
    puts "Net Audit: Comparing $namedCount nets for similarities..."

    set issues {}
    set issueCount 0

    for {set i 0} {$i < $namedCount} {incr i} {
        set n1 [lindex $namedNets $i]
        for {set j [expr {$i + 1}]} {$j < $namedCount} {incr j} {
            set n2 [lindex $namedNets $j]
            set code [capNetAudit_checkSimilar $n1 $n2]
            if {$code > 0} {
                set desc [capNetAudit_descSimilar $code]
                lappend issues [list $n1 $n2 $desc $code]
                incr issueCount
            }
        }
    }

    # ------------------------------------------------------------------
    # Step 6: Check for single-connection nets (possible dangling)
    # ------------------------------------------------------------------
    set lStatus3 [DboState]
    set danglingNets {}

    set lNetIter2 [$objDesign NewFlatNetsIter $lStatus3]
    set lFlatNet2 [$lNetIter2 NextFlatNet $lStatus3]

    while {$lFlatNet2 != $lNullObj} {
        set lNameCS2 [DboTclHelper_sMakeCString]
        $lFlatNet2 GetName $lNameCS2
        set lNetName2 [DboTclHelper_sGetConstCharPtr $lNameCS2]

        # Skip auto-generated nets
        if {$lNetName2 != "" && ![regexp {^N\d{4,}$} $lNetName2]} {
            # Count port occurrences (connections)
            set connCount 0
            set lPinIter [$lFlatNet2 NewPortOccurrencesIter $lStatus3]
            set lPin [$lPinIter NextPortOccurrence $lStatus3]
            while {$lPin != $lNullObj} {
                incr connCount
                set lPin [$lPinIter NextPortOccurrence $lStatus3]
            }
            delete_DboFlatNetPortOccurrencesIter $lPinIter

            if {$connCount == 1} {
                lappend danglingNets $lNetName2
            }
        }

        set lFlatNet2 [$lNetIter2 NextFlatNet $lStatus3]
    }
    delete_DboDesignFlatNetsIter $lNetIter2
    $lStatus3 -delete

    set danglingCount [llength $danglingNets]

    # ------------------------------------------------------------------
    # Step 7: Show report in Tk window
    # ------------------------------------------------------------------
    puts "Net Audit: Analysis complete. $issueCount similar pairs, $danglingCount single-conn nets."

    capNetAudit_showReport $namedCount $autoCount $issues $danglingNets
}

# ======================================================================
# Report window (Tk)
# ======================================================================
proc capNetAudit_showReport {namedCount autoCount issues danglingNets} {

    set issueCount [llength $issues]
    set danglingCount [llength $danglingNets]

    set w .capNetAuditReport
    catch {destroy $w}

    toplevel $w
    wm title $w "Net Name Audit Report"
    wm geometry $w 720x520
    wm minsize $w 600 400

    # Summary bar
    set summary "$namedCount named nets | $autoCount auto-gen skipped | $issueCount similar pairs | $danglingCount single-conn"
    label $w.summary -text $summary -font {{Microsoft YaHei UI} 10 bold} \
        -bg "#16213e" -fg "#e8eaf6" -anchor w -padx 12 -pady 8
    pack $w.summary -fill x

    # Notebook with two tabs
    ttk::notebook $w.nb
    pack $w.nb -fill both -expand 1 -padx 8 -pady 4

    # ── Tab 1: Similar net pairs ──────────────────────────────────────
    set f1 [ttk::frame $w.nb.similar]
    $w.nb add $f1 -text " Similar Nets ($issueCount) "

    set cols {net1 net2 reason}
    ttk::treeview $f1.tree -columns $cols -show headings -height 16
    $f1.tree heading net1 -text "Net A"
    $f1.tree heading net2 -text "Net B"
    $f1.tree heading reason -text "Issue"
    $f1.tree column net1 -width 220 -anchor w
    $f1.tree column net2 -width 220 -anchor w
    $f1.tree column reason -width 200 -anchor w

    ttk::scrollbar $f1.sb -orient vertical -command [list $f1.tree yview]
    $f1.tree configure -yscrollcommand [list $f1.sb set]

    pack $f1.sb -side right -fill y
    pack $f1.tree -fill both -expand 1

    # Sort issues: case diff first, then edit dist, then base, then underscore
    set sorted [lsort -index 3 -integer $issues]

    foreach item $sorted {
        set n1   [lindex $item 0]
        set n2   [lindex $item 1]
        set desc [lindex $item 2]
        $f1.tree insert {} end -values [list $n1 $n2 $desc]
    }

    # ── Tab 2: Single-connection (dangling) nets ──────────────────────
    set f2 [ttk::frame $w.nb.dangling]
    $w.nb add $f2 -text " Single-Connection ($danglingCount) "

    set cols2 {netname note}
    ttk::treeview $f2.tree -columns $cols2 -show headings -height 16
    $f2.tree heading netname -text "Net Name"
    $f2.tree heading note -text "Note"
    $f2.tree column netname -width 300 -anchor w
    $f2.tree column note -width 350 -anchor w

    ttk::scrollbar $f2.sb -orient vertical -command [list $f2.tree yview]
    $f2.tree configure -yscrollcommand [list $f2.sb set]

    pack $f2.sb -side right -fill y
    pack $f2.tree -fill both -expand 1

    foreach dn [lsort $danglingNets] {
        set note "Only 1 connection - possible dangling net"
        if {[regexp -nocase {^(vcc|vdd|gnd|vss|pgnd|agnd)} $dn]} {
            set note "Power net with only 1 connection"
        }
        $f2.tree insert {} end -values [list $dn $note]
    }

    # Bottom bar
    frame $w.bottom -bg "#edf0f5" -height 36
    pack $w.bottom -fill x -side bottom

    button $w.bottom.close -text "Close" -command [list destroy $w] \
        -font {{Microsoft YaHei UI} 10} -padx 16 -pady 4
    pack $w.bottom.close -side right -padx 8 -pady 4

    label $w.bottom.hint -text "Tip: Review case diffs and edit-dist=1 pairs carefully" \
        -font {{Microsoft YaHei UI} 9} -fg "#666" -bg "#edf0f5"
    pack $w.bottom.hint -side left -padx 8

    puts "Net Audit: Report window opened."
}

# ======================================================================
# Registration
# ======================================================================
proc capNetAudit_register {} {
    RegisterAction "_cdnCapActionNetAudit" "capNetAudit_shouldProcess" "" "capNetAudit_execute" ""
    RegisterAction "_cdnCapUpdateNetAudit" "capNetAudit_shouldProcess" "" "capNetAudit_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsNetNameAudit"] "" "" [list "action" "Net Name &Audit" "0" "_cdnCapActionNetAudit" "_cdnCapUpdateNetAudit" "" "" "" "Scan design for similar/suspicious net names and dangling nets"] ""]
}

capNetAudit_register
