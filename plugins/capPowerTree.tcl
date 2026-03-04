#############################################################################
# capPowerTree.tcl
# OrCAD Capture CIS 23.1 Plugin
#
# @Plugin-Name:  Power Tree Extractor
# @Version:      2.0.0
# @Author:       KAIDOU.WU
# @Menu:         Tools > Export Power Tree
# @Description:  提取电源网络拓扑，自动分析层级关系，生成HTML电源树图
#############################################################################

proc capPowerTree_shouldProcess {args} { return true }
proc capPowerTree_enable {args} { return true }

# ─── Pin type enum to string ────────────────────────────────────────────
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

# ─── HTML escape ────────────────────────────────────────────────────────
proc capPowerTree_htmlEscape {str} {
    return [string map {& &amp; < &lt; > &gt; \" &quot;} $str]
}

# ─── Classify component role from Part Name + Value + RefDes ────────────
proc capPowerTree_classifyComponent {partName value refdes} {
    set pn [string toupper $partName]
    set val [string toupper $value]
    set ref [string toupper $refdes]
    set search "$pn $val"

    if {[regexp {LDO|AMS1117|HT73|ME6211|RT9013|AP2112|MIC5504|TLV70|TPS7A|LP2985|LP5907|NCV8|SPX3819|XC6206|XC6220|ETA5055|SGM2019|SGM2036|NCP16|MCP1700|AP7370|AP7380} $search]} { return "LDO" }
    if {[regexp {DCDC|DC-DC|TPS5|TPS6|LM25|LM26|MP1|MP2|SY8|RT7|RT8|AOZ|NCP|LMR|TLV6|AP63|AP64|SIC4|MT2|MT3|XL|ETA2865|ETA3425|SGM6603|SYR8|TPS54|TPS62|LM267|MPQ} $search]} { return "DCDC" }
    if {[regexp {CJAB|CJAC|AO34|SI23|BSS138|2N7002|IRLML} $search]} { return "MOSFET" }
    if {[regexp {ETA4553|TXB0|TXS0|GTL2002|SN74|LSF0|NVT20} $search]} { return "LEVEL_SHIFTER" }
    if {[regexp {^FB} $ref]} { return "FERRITE_BEAD" }
    if {[regexp {^L} $ref] && [regexp {R.*MHZ} $val]} { return "FERRITE_BEAD" }
    if {[regexp {^L} $ref]} { return "INDUCTOR" }
    if {[regexp {^C} $ref]} { return "CAP" }
    if {[regexp {^R} $ref]} { return "RES" }
    if {[regexp {^D} $ref]} { return "DIODE" }
    if {[regexp {^J|^P[0-9]|^CN|CONN} $ref]} { return "CONNECTOR" }
    if {[regexp {^TP} $ref]} { return "TEST_POINT" }
    if {[regexp {^X|^Y} $ref]} { return "CRYSTAL" }
    if {[regexp {^S[0-9]} $ref]} { return "SWITCH_MECH" }
    if {[regexp {^U} $ref]} { return "IC" }
    return "OTHER"
}

# ─── Is this net name a power rail? ─────────────────────────────────────
proc capPowerTree_isPowerNet {netName} {
    set n [string toupper $netName]
    if {[regexp {^N\d+$} $netName]} { return 0 }
    if {[regexp {^V(CC|DD|BUS|OUT|BAT|SYS|REF|IN)($|[_0-9])} $n]} { return 1 }
    if {[regexp {^V[+-]} $n]} { return 1 }
    if {[regexp {^\+?[0-9]+\.?[0-9]*V[0-9]*$} $n]} { return 1 }
    if {[regexp {^GND($|_)} $n]}  { return 1 }
    if {[regexp {^[ADP]GND($|_)} $n]} { return 1 }
    if {[regexp {(^|_)(VCC|VDD|VBUS|VBAT|VSYS)($|_)} $n]} { return 1 }
    return 0
}

# ─── Is this a GND net? ────────────────────────────────────────────────
proc capPowerTree_isGndNet {netName} {
    set n [string toupper $netName]
    if {[regexp {^GND($|_)} $n]} { return 1 }
    if {[regexp {^[ADP]GND($|_)} $n]} { return 1 }
    if {[regexp {VSS} $n]} { return 1 }
    return 0
}

# ─── Extract voltage from net name (e.g. VCC_3V3 → 3.3) ───────────────
proc capPowerTree_extractVoltage {netName} {
    set n [string toupper $netName]
    if {[regexp {(\d+)V(\d+)} $n _ whole frac]} {
        return "${whole}.${frac}"
    }
    if {[regexp {(\d+)V$} $n _ whole]} {
        return "${whole}"
    }
    if {[regexp {(\d+\.\d+)V} $n _ v]} {
        return $v
    }
    if {[regexp {VBUS|USB} $n]} { return "5" }
    if {[regexp {VOUT} $n]} { return "?" }
    return "?"
}

# ─── Is this pin name an input pin of a regulator? ─────────────────────
proc capPowerTree_isRegulatorInputPin {pinName} {
    set p [string toupper $pinName]
    if {[regexp {^(VIN|IN|INPUT|AVIN|PVIN|VCC|VSUP|SUP|EN)$} $p]} { return 1 }
    if {[regexp {^IN[0-9]*$} $p]} { return 1 }
    return 0
}

# ─── Is this pin name an output pin of a regulator? ────────────────────
proc capPowerTree_isRegulatorOutputPin {pinName} {
    set p [string toupper $pinName]
    if {[regexp {^(VOUT|OUT|OUTPUT|SW|LX|FB)$} $p]} { return 1 }
    if {[regexp {^OUT[0-9]*$} $p]} { return 1 }
    return 0
}

# ─── Progress window ───────────────────────────────────────────────────
proc capPowerTree_progressCreate {title} {
    catch {destroy .ptProg}
    toplevel .ptProg
    wm title .ptProg $title
    wm geometry .ptProg 450x120
    wm resizable .ptProg 0 0
    wm attributes .ptProg -topmost 1
    .ptProg configure -background "#1e1e2e"

    label .ptProg.step -text "准备中..." \
        -font {{Microsoft YaHei} 10} -fg "#e0e0e0" -bg "#1e1e2e"
    canvas .ptProg.bar -width 410 -height 22 -bg "#2a2a3e" \
        -highlightthickness 0
    .ptProg.bar create rectangle 0 0 0 22 -fill "#00b4d8" -tags fill
    label .ptProg.detail -text "" \
        -font {{Microsoft YaHei} 8} -fg "#888" -bg "#1e1e2e"

    pack .ptProg.step   -padx 20 -pady {12 4} -anchor w
    pack .ptProg.bar    -padx 20 -pady 2
    pack .ptProg.detail -padx 20 -pady {2 8} -anchor w
    update idletasks
}

proc capPowerTree_progressUpdate {pct stepText {detail ""}} {
    if {![winfo exists .ptProg]} return
    set w [expr {int(410.0 * $pct / 100)}]
    .ptProg.bar coords fill 0 0 $w 22
    .ptProg.step configure -text $stepText
    .ptProg.detail configure -text $detail
    update idletasks
}

proc capPowerTree_progressDestroy {} {
    catch {destroy .ptProg}
}

# =========================================================================
# HTML Generation — builds a self-contained power tree diagram
# =========================================================================
proc capPowerTree_generateHTML {designName powerNets components lHtmlPath} {

    # ── Step A: Build regulator-to-net mapping ──────────────────────
    # For each regulator (LDO/DCDC), find which power net is input
    # and which is output by checking pin names.
    # regulators: dict refdes -> {inputNet outputNet value role}

    set regulators [dict create]
    set regulatorRoles {LDO DCDC}

    dict for {netName pins} $powerNets {
        foreach p $pins {
            set ref     [lindex $p 0]
            set pinName [lindex $p 2]
            set value   [lindex $p 5]
            set role    [lindex $p 6]

            if {$role ni $regulatorRoles} continue

            if {![dict exists $regulators $ref]} {
                dict set regulators $ref [dict create inputNet "" outputNet "" value $value role $role nets [list]]
            }

            set entry [dict get $regulators $ref]
            set netList [dict get $entry nets]
            if {$netName ni $netList} {
                lappend netList $netName
                dict set entry nets $netList
            }

            if {[capPowerTree_isRegulatorInputPin $pinName]} {
                dict set entry inputNet $netName
            } elseif {[capPowerTree_isRegulatorOutputPin $pinName]} {
                dict set entry outputNet $netName
            }

            dict set regulators $ref $entry
        }
    }

    # For regulators where pin names didn't resolve, use heuristic:
    # higher voltage net = input, lower voltage net = output
    dict for {ref entry} $regulators {
        set inNet  [dict get $entry inputNet]
        set outNet [dict get $entry outputNet]
        set nets   [dict get $entry nets]

        if {($inNet == "" || $outNet == "") && [llength $nets] >= 2} {
            set netVolts {}
            foreach n $nets {
                if {[capPowerTree_isGndNet $n]} continue
                set v [capPowerTree_extractVoltage $n]
                if {$v != "?"} {
                    lappend netVolts [list $n $v]
                }
            }
            if {[llength $netVolts] >= 2} {
                set netVolts [lsort -index 1 -real -decreasing $netVolts]
                if {$inNet == ""} {
                    dict set entry inputNet [lindex [lindex $netVolts 0] 0]
                }
                if {$outNet == ""} {
                    dict set entry outputNet [lindex [lindex $netVolts end] 0]
                }
                dict set regulators $ref $entry
            }
        }
    }

    # ── Step B: Build tree edges ────────────────────────────────────
    # parentOf: dict  outputNet -> {inputNet regulatorRef regulatorValue regulatorRole}
    set parentOf [dict create]
    dict for {ref entry} $regulators {
        set inNet  [dict get $entry inputNet]
        set outNet [dict get $entry outputNet]
        if {$inNet != "" && $outNet != "" && $inNet != $outNet} {
            dict set parentOf $outNet [list $inNet $ref [dict get $entry value] [dict get $entry role]]
        }
    }

    # ── Step C: Find root nets (no parent = input sources) ──────────
    set allPowerNets {}
    dict for {netName _} $powerNets {
        if {![capPowerTree_isGndNet $netName]} {
            lappend allPowerNets $netName
        }
    }

    set rootNets {}
    foreach n $allPowerNets {
        if {![dict exists $parentOf $n]} {
            lappend rootNets $n
        }
    }

    # ── Step D: Build children map ──────────────────────────────────
    # childrenOf: dict  netName -> list of childNet
    set childrenOf [dict create]
    dict for {childNet info} $parentOf {
        set parentNet [lindex $info 0]
        if {![dict exists $childrenOf $parentNet]} {
            dict set childrenOf $parentNet [list]
        }
        set kids [dict get $childrenOf $parentNet]
        lappend kids $childNet
        dict set childrenOf $parentNet $kids
    }

    # ── Step E: Collect loads per net (non-regulator ICs) ───────────
    # loads: dict netName -> list of {ref value role}
    set loadsOf [dict create]
    set passiveRoles {CAP RES FERRITE_BEAD INDUCTOR TEST_POINT DIODE CRYSTAL SWITCH_MECH OTHER}
    dict for {netName pins} $powerNets {
        if {[capPowerTree_isGndNet $netName]} continue
        set loadList {}
        foreach p $pins {
            set ref  [lindex $p 0]
            set val  [lindex $p 5]
            set role [lindex $p 6]
            if {$role in $passiveRoles} continue
            if {$role in $regulatorRoles && [dict exists $regulators $ref]} continue
            if {$ref == ""} continue
            set already 0
            foreach existing $loadList {
                if {[lindex $existing 0] == $ref} { set already 1; break }
            }
            if {!$already} {
                lappend loadList [list $ref $val $role]
            }
        }
        if {[llength $loadList] > 0} {
            dict set loadsOf $netName $loadList
        }
    }

    # ── Step F: Count caps per net ──────────────────────────────────
    set capsOf [dict create]
    dict for {netName pins} $powerNets {
        if {[capPowerTree_isGndNet $netName]} continue
        set capCount 0
        foreach p $pins {
            if {[lindex $p 6] == "CAP"} { incr capCount }
        }
        dict set capsOf $netName $capCount
    }

    # ── Step G: GND net stats ───────────────────────────────────────
    set gndNets {}
    set gndPinCount 0
    dict for {netName pins} $powerNets {
        if {[capPowerTree_isGndNet $netName]} {
            lappend gndNets $netName
            incr gndPinCount [llength $pins]
        }
    }

    # ── Step H: Write HTML ──────────────────────────────────────────
    set fh [open $lHtmlPath w]
    fconfigure $fh -encoding utf-8

    set escapedDesign [capPowerTree_htmlEscape $designName]

    puts $fh "<!DOCTYPE html>"
    puts $fh "<html lang=\"zh-CN\"><head><meta charset=\"UTF-8\">"
    puts $fh "<title>电源树 - $escapedDesign</title>"
    puts $fh "<style>"
    puts $fh "* { margin:0; padding:0; box-sizing:border-box; }"
    puts $fh "body { font-family:'Segoe UI','Microsoft YaHei',sans-serif; background:#121220; color:#e0e0e0; padding:24px; }"
    puts $fh "h1 { color:#00d4ff; font-size:22px; margin-bottom:4px; }"
    puts $fh ".subtitle { color:#888; font-size:13px; margin-bottom:20px; }"
    puts $fh ".tree { position:relative; padding:20px 0 20px 0; }"
    puts $fh ".node { display:inline-block; border-radius:8px; padding:10px 14px; margin:6px 4px; min-width:160px; vertical-align:top; border:1px solid rgba(255,255,255,0.1); }"
    puts $fh ".node .net-name { font-weight:bold; font-size:14px; margin-bottom:2px; }"
    puts $fh ".node .voltage { font-size:20px; font-weight:bold; margin:4px 0; }"
    puts $fh ".node .info { font-size:11px; color:#aaa; }"
    puts $fh ".node .chips { font-size:11px; color:#ccc; margin-top:4px; }"
    puts $fh ".node .chip { display:inline-block; background:rgba(255,255,255,0.08); border-radius:3px; padding:1px 6px; margin:2px 2px 0 0; font-size:10px; }"
    puts $fh ".root    { background:linear-gradient(135deg,#e65100,#f57c00); color:#fff; border-color:#ff9800; }"
    puts $fh ".dcdc    { background:linear-gradient(135deg,#0d47a1,#1976d2); color:#fff; border-color:#42a5f5; }"
    puts $fh ".ldo     { background:linear-gradient(135deg,#1b5e20,#388e3c); color:#fff; border-color:#66bb6a; }"
    puts $fh ".rail    { background:#1e1e2e; border-color:#444; }"
    puts $fh ".gnd     { background:linear-gradient(135deg,#37474f,#546e7a); color:#ddd; border-color:#78909c; }"
    puts $fh ".level { display:flex; align-items:flex-start; margin:8px 0; }"
    puts $fh ".level-label { writing-mode:vertical-lr; text-orientation:mixed; font-size:11px; color:#666; padding:8px 8px 8px 0; min-width:30px; letter-spacing:2px; }"
    puts $fh ".level-nodes { display:flex; flex-wrap:wrap; align-items:flex-start; }"
    puts $fh ".arrow { text-align:center; color:#555; font-size:20px; padding:2px 0; }"
    puts $fh ".legend { display:flex; gap:16px; margin:16px 0; flex-wrap:wrap; }"
    puts $fh ".legend-item { display:flex; align-items:center; gap:6px; font-size:12px; color:#aaa; }"
    puts $fh ".legend-dot { width:12px; height:12px; border-radius:3px; }"
    puts $fh ".summary { background:#1a1a2e; border:1px solid #333; border-radius:10px; padding:20px; margin-top:24px; }"
    puts $fh ".summary h2 { color:#00d4ff; font-size:16px; margin-bottom:12px; }"
    puts $fh ".summary ul { list-style:none; padding:0; }"
    puts $fh ".summary li { padding:3px 0; font-size:13px; color:#ccc; }"
    puts $fh ".summary li::before { content:'▸ '; color:#00b4d8; }"
    puts $fh ".cols { display:grid; grid-template-columns:1fr 1fr; gap:20px; }"
    puts $fh "@media(max-width:800px) { .cols { grid-template-columns:1fr; } }"
    puts $fh "</style></head><body>"

    puts $fh "<h1>⚡ 电源树 — $escapedDesign</h1>"
    puts $fh "<div class=\"subtitle\">[llength $allPowerNets] 个电源网络 · [llength $gndNets] 个接地网络 · [dict size $regulators] 个稳压器</div>"

    puts $fh "<div class=\"legend\">"
    puts $fh "<div class=\"legend-item\"><div class=\"legend-dot\" style=\"background:#f57c00\"></div>输入源</div>"
    puts $fh "<div class=\"legend-item\"><div class=\"legend-dot\" style=\"background:#1976d2\"></div>DCDC</div>"
    puts $fh "<div class=\"legend-item\"><div class=\"legend-dot\" style=\"background:#388e3c\"></div>LDO</div>"
    puts $fh "<div class=\"legend-item\"><div class=\"legend-dot\" style=\"background:#333\"></div>电源轨</div>"
    puts $fh "<div class=\"legend-item\"><div class=\"legend-dot\" style=\"background:#546e7a\"></div>GND</div>"
    puts $fh "</div>"

    # ── Recursive node renderer ─────────────────────────────────────
    # Renders a power net node and its children (DFS)
    proc renderNode {fh netName parentOf childrenOf regulators loadsOf capsOf depth} {
        set voltage [capPowerTree_extractVoltage $netName]
        set escapedNet [capPowerTree_htmlEscape $netName]
        set capCnt 0
        if {[dict exists $capsOf $netName]} {
            set capCnt [dict get $capsOf $netName]
        }

        if {[dict exists $parentOf $netName]} {
            set regInfo [dict get $parentOf $netName]
            set regRef [lindex $regInfo 1]
            set regVal [lindex $regInfo 2]
            set regRole [lindex $regInfo 3]
            set cssClass [string tolower $regRole]
            set regLabel "[capPowerTree_htmlEscape $regRef]: [capPowerTree_htmlEscape $regVal]"
        } elseif {$depth == 0} {
            set cssClass "root"
            set regLabel "输入源"
        } else {
            set cssClass "rail"
            set regLabel ""
        }

        puts $fh "<div class=\"node $cssClass\">"
        puts $fh "<div class=\"net-name\">$escapedNet</div>"
        if {$voltage != "?"} {
            puts $fh "<div class=\"voltage\">${voltage}V</div>"
        }
        if {$regLabel != ""} {
            puts $fh "<div class=\"info\">$regLabel</div>"
        }
        if {$capCnt > 0} {
            puts $fh "<div class=\"info\">${capCnt}× 去耦电容</div>"
        }

        if {[dict exists $loadsOf $netName]} {
            puts $fh "<div class=\"chips\">"
            foreach ld [dict get $loadsOf $netName] {
                set ldRef [capPowerTree_htmlEscape [lindex $ld 0]]
                set ldVal [capPowerTree_htmlEscape [lindex $ld 1]]
                set ldRole [lindex $ld 2]
                puts $fh "<span class=\"chip\" title=\"$ldVal ($ldRole)\">$ldRef</span>"
            }
            puts $fh "</div>"
        }
        puts $fh "</div>"

        if {[dict exists $childrenOf $netName]} {
            set kids [dict get $childrenOf $netName]
            if {[llength $kids] > 0} {
                puts $fh "<div style=\"margin-left:32px; border-left:2px solid #333; padding-left:12px;\">"
                puts $fh "<div class=\"arrow\">↓</div>"
                foreach child $kids {
                    renderNode $fh $child $parentOf $childrenOf $regulators $loadsOf $capsOf [expr {$depth + 1}]
                }
                puts $fh "</div>"
            }
        }
    }

    puts $fh "<div class=\"tree\">"
    foreach rootNet $rootNets {
        renderNode $fh $rootNet $parentOf $childrenOf $regulators $loadsOf $capsOf 0
    }

    # Orphan power nets (not root, not child of anything with a parent chain to root)
    set rendered [dict create]
    proc collectRendered {netName childrenOf rendered_var} {
        upvar $rendered_var r
        dict set r $netName 1
        if {[dict exists $childrenOf $netName]} {
            foreach child [dict get $childrenOf $netName] {
                collectRendered $child $childrenOf r
            }
        }
    }
    foreach rootNet $rootNets {
        collectRendered $rootNet $childrenOf rendered
    }

    set orphans {}
    foreach n $allPowerNets {
        if {![dict exists $rendered $n]} {
            lappend orphans $n
        }
    }
    if {[llength $orphans] > 0} {
        puts $fh "<div style=\"margin-top:16px; padding-top:12px; border-top:1px solid #333;\">"
        puts $fh "<div style=\"color:#888; font-size:12px; margin-bottom:8px;\">其他电源网络（未能自动归入树）：</div>"
        foreach n $orphans {
            renderNode $fh $n $parentOf $childrenOf $regulators $loadsOf $capsOf 0
        }
        puts $fh "</div>"
    }

    # GND
    if {[llength $gndNets] > 0} {
        puts $fh "<div style=\"margin-top:16px; padding-top:12px; border-top:1px solid #333;\">"
        puts $fh "<div class=\"arrow\">↓</div>"
        foreach gn $gndNets {
            set escapedGnd [capPowerTree_htmlEscape $gn]
            set gndPins 0
            if {[dict exists $powerNets $gn]} {
                set gndPins [llength [dict get $powerNets $gn]]
            }
            puts $fh "<div class=\"node gnd\">"
            puts $fh "<div class=\"net-name\">$escapedGnd</div>"
            puts $fh "<div class=\"voltage\">0V</div>"
            puts $fh "<div class=\"info\">${gndPins} 个连接</div>"
            puts $fh "</div>"
        }
        puts $fh "</div>"
    }

    puts $fh "</div>"

    # ── Summary section ─────────────────────────────────────────────
    puts $fh "<div class=\"summary\">"
    puts $fh "<h2>电源分析摘要</h2>"
    puts $fh "<div class=\"cols\">"

    puts $fh "<div><h3 style=\"color:#aaa;font-size:13px;margin-bottom:8px;\">电压路径</h3><ul>"
    proc printPaths {fh netName parentOf childrenOf regulators path} {
        set voltage [capPowerTree_extractVoltage $netName]
        set vStr "${netName}"
        if {[dict exists $parentOf $netName]} {
            set regInfo [dict get $parentOf $netName]
            set regRef [lindex $regInfo 1]
            set regRole [lindex $regInfo 3]
            set newPath "${path} → ${regRef}(${regRole}) → ${vStr}"
        } else {
            set newPath $vStr
        }

        if {[dict exists $childrenOf $netName]} {
            foreach child [dict get $childrenOf $netName] {
                printPaths $fh $child $parentOf $childrenOf $regulators $newPath
            }
        } else {
            puts $fh "<li>[capPowerTree_htmlEscape $newPath]</li>"
        }
    }
    foreach rootNet $rootNets {
        printPaths $fh $rootNet $parentOf $childrenOf $regulators ""
    }
    puts $fh "</ul></div>"

    puts $fh "<div><h3 style=\"color:#aaa;font-size:13px;margin-bottom:8px;\">稳压器</h3><ul>"
    dict for {ref entry} $regulators {
        set role [dict get $entry role]
        set val  [dict get $entry value]
        set inN  [dict get $entry inputNet]
        set outN [dict get $entry outputNet]
        set inV  [capPowerTree_extractVoltage $inN]
        set outV [capPowerTree_extractVoltage $outN]
        set line "[capPowerTree_htmlEscape $ref] ($role): [capPowerTree_htmlEscape $val]"
        if {$inN != "" && $outN != ""} {
            append line " — ${inV}V → ${outV}V"
        }
        puts $fh "<li>$line</li>"
    }
    puts $fh "</ul></div>"

    puts $fh "</div></div>"

    puts $fh "</body></html>"
    close $fh
}

# =========================================================================
# Main
# =========================================================================
proc capPowerTree_execute {} {

    set lNullObj "NULL"

    set objDesign [GetActivePMDesign]
    if {$objDesign == "" || $objDesign == $lNullObj} {
        puts "Power Tree: ERROR - No active design."
        return
    }

    set lDesignName [DboTclHelper_sMakeCString]
    $objDesign GetName $lDesignName
    set lDesignPath [DboTclHelper_sGetConstCharPtr $lDesignName]
    set lDesignBaseName [file rootname [file tail $lDesignPath]]

    capPowerTree_progressCreate "电源树导出 - $lDesignBaseName"
    capPowerTree_progressUpdate 0 "\[1/3\] 正在扫描网络..."

    # ── Count nets first for progress ───────────────────────────────
    set lStatus [DboState]
    set netIter [$objDesign NewFlatNetsIter $lStatus]
    if {$netIter == $lNullObj || $netIter == ""} {
        capPowerTree_progressDestroy
        puts "Power Tree: ERROR - Cannot create flat net iterator."
        return
    }
    set totalNetCount 0
    set net [$netIter NextFlatNet $lStatus]
    while {$net != $lNullObj && $net != ""} {
        incr totalNetCount
        set net [$netIter NextFlatNet $lStatus]
    }
    delete_DboDesignFlatNetsIter $netIter

    # ── Scan nets ───────────────────────────────────────────────────
    set netIter [$objDesign NewFlatNetsIter $lStatus]
    set powerNets [dict create]
    set components [dict create]
    set allNetCount 0
    set powerNetCount 0

    set net [$netIter NextFlatNet $lStatus]
    while {$net != $lNullObj && $net != ""} {
        incr allNetCount

        if {$totalNetCount > 0 && ($allNetCount % 5 == 0 || $allNetCount == $totalNetCount)} {
            set pct [expr {int(60.0 * $allNetCount / $totalNetCount)}]
            capPowerTree_progressUpdate $pct \
                "\[1/3\] 扫描网络 ($allNetCount/$totalNetCount)" \
                "已发现 $powerNetCount 个电源网络"
        }

        set netNameCS [DboTclHelper_sMakeCString]
        $net GetName $netNameCS
        set netName [DboTclHelper_sGetConstCharPtr $netNameCS]

        set isPower [capPowerTree_isPowerNet $netName]

        set pinIter [$net NewPortOccurrencesIter $lStatus]
        set pinList {}
        set pinCount 0

        if {$pinIter != $lNullObj && $pinIter != ""} {
            set pin [$pinIter NextPortOccurrence $lStatus]
            while {$pin != $lNullObj && $pin != ""} {
                incr pinCount
                set pinInst [$pin GetPortInst $lStatus]
                if {$pinInst != $lNullObj && $pinInst != ""} {
                    set ptype [$pinInst GetPinType $lStatus]
                    set ptypeStr [capPowerTree_pinTypeStr $ptype]

                    set pinNumCS [DboTclHelper_sMakeCString]
                    $pinInst GetPinNumber $pinNumCS
                    set pinNum [DboTclHelper_sGetConstCharPtr $pinNumCS]

                    set pinNameCS [DboTclHelper_sMakeCString]
                    $pinInst GetPinName $pinNameCS
                    set pinName [DboTclHelper_sGetConstCharPtr $pinNameCS]

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

                    set role [capPowerTree_classifyComponent $partName $partValue $refdes]
                    lappend pinList [list $refdes $pinNum $pinName $ptypeStr $partName $partValue $role]
                    if {$refdes != "" && ![dict exists $components $refdes]} {
                        dict set components $refdes [list $partName $partValue $role]
                    }
                }
                set pin [$pinIter NextPortOccurrence $lStatus]
            }
            delete_DboFlatNetPortOccurrencesIter $pinIter
        }

        if {$isPower && $pinCount > 0} {
            dict set powerNets $netName $pinList
            incr powerNetCount
        }

        set net [$netIter NextFlatNet $lStatus]
    }
    delete_DboDesignFlatNetsIter $netIter

    capPowerTree_progressUpdate 65 "\[1/3\] 扫描完成" \
        "$powerNetCount 个电源网络, [dict size $components] 个器件"

    if {$powerNetCount == 0} {
        capPowerTree_progressDestroy
        puts "Power Tree: WARNING - No power nets found."
        return
    }

    # ── Choose save location ────────────────────────────────────────
    capPowerTree_progressUpdate 68 "\[2/3\] 选择保存位置..."

    set lDesignDir [file dirname [file normalize $lDesignPath]]

    set lSaveDir ""
    if {[catch {
        set lInitDir [DboTclHelper_sMakeCString $lDesignDir]
        set lChosenPath [capOpenArchiveDialog $lInitDir]
        set lSaveDir [DboTclHelper_sGetConstCharPtr $lChosenPath]
    } errMsg]} {
        if {[catch {
            set lSaveDir [tk_chooseDirectory \
                -title "导出电源树 - 选择保存目录" -initialdir $lDesignDir]
        } errMsg2]} {
            set lSaveDir ""
        }
    }

    if {$lSaveDir == ""} {
        capPowerTree_progressDestroy
        puts "Power Tree: User cancelled."
        return
    }

    set lHtmlPath [file join $lSaveDir "${lDesignBaseName}_powertree.html"]

    # ── Generate HTML ───────────────────────────────────────────────
    capPowerTree_progressUpdate 75 "\[3/3\] 生成电源树 HTML..." $lHtmlPath

    capPowerTree_generateHTML $lDesignBaseName $powerNets $components $lHtmlPath

    capPowerTree_progressUpdate 100 "完成！" $lHtmlPath

    puts "Power Tree: ================================================"
    puts "Power Tree: HTML: $lHtmlPath"
    puts "Power Tree: Power nets: $powerNetCount"
    puts "Power Tree: Components: [dict size $components]"
    puts "Power Tree: ================================================"

    after 2000 capPowerTree_progressDestroy
    catch {exec cmd /c start "" $lHtmlPath &}
}

# ─── Registration ───────────────────────────────────────────────────────
proc capPowerTree_register {} {
    RegisterAction "_cdnCapActionPowerTree" "capPowerTree_shouldProcess" "" "capPowerTree_execute" ""
    RegisterAction "_cdnCapUpdatePowerTree" "capPowerTree_shouldProcess" "" "capPowerTree_enable" ""
    InsertXMLMenu [list [list "Tools" "ToolsExportPowerTree"] "" "" [list "action" "Export Power &Tree" "0" "_cdnCapActionPowerTree" "_cdnCapUpdatePowerTree" "" "" "" "Export power tree topology as HTML"] ""]
}

capPowerTree_register
